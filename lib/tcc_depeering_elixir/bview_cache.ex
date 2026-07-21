defmodule TccDepeeringElixir.BViewCache do
  @moduledoc """
  Caches parsed bgpdump results in ETS with JSON persistence.
  
  - In-memory ETS table for fast access
  - Separate JSON cache file per date+time (doing it in a single file would make it grow indefinitely) 
  """

  @cache_dir "data/cache"

  @doc """
  Parse file with caching. Returns cached result if file hasn't changed.
  
  Returns:
    {:ok, parse_result, cached: boolean}
    {:error, reason}
  """ 
  def parse_or_cache(file_path, rrc, opts \\ []) do
    ip_version = opts[:ip_version] || "v4"
    event_id = opts[:event_id]
    origin_asn = opts[:origin_asn]
    
    IO.puts("Checking cache for #{file_path} (RRC: #{rrc}, IP Version: #{ip_version}, origin_asn: #{origin_asn})")
    case check_cache(file_path, rrc, origin_asn, ip_version) do
      {:hit, result} ->
        {:ok, result, cached: true}

      :miss ->
        # Update event to parsing state if we have an event ID
        if event_id do
          TccDepeeringElixir.BViewEventPersistence.update_event_state(event_id, "parsing")
        end
        
        case TccDepeeringElixir.BViewParser.parse_file(file_path, opts) do
          {:ok, result} ->
            store_cache(file_path, result, rrc, origin_asn, ip_version)
            
            # Complete the event when parsing finishes
            if event_id do
              TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
            end
            
            {:ok, result, cached: false}

          {:error, reason} -> 
            IO.warn("Parsing failed for #{file_path}: #{reason}")
            {:error, reason}
        end
    end
  end

  @doc """
  Clear all cache entries.
  """
  def clear_all do
    File.rm_rf(@cache_dir)
    File.mkdir_p(@cache_dir)
  end

  @doc """
  Clear cache for a specific file.
  """
  def clear(file_path, rrc, origin_asn, ip_version) do
    cache_file = get_cache_file_path(file_path, rrc, origin_asn, ip_version)
    File.rm(cache_file)
  end

  @doc """
  Get cache stats.
  """
  def stats do
    case File.ls(@cache_dir) do
      {:ok, rrc_dirs} ->
        count = Enum.reduce(rrc_dirs, 0, fn rrc_dir, acc ->
          case File.ls(Path.join(@cache_dir, rrc_dir)) do
            {:ok, files} -> acc + Enum.count(files)
            {:error, _} -> acc
          end
        end)
        %{cached_files: count}
      {:error, _} ->
        %{cached_files: 0}
    end
  end

  defp check_cache(file_path, rrc, origin_asn, ip_version) do
    cache_file = get_cache_file_path(file_path, rrc, origin_asn, ip_version)
    IO.puts("Looking for cache file: #{cache_file}")
    case File.read(cache_file) do
      {:ok, json_content} ->
        try do
          cache_entry = Jason.decode!(json_content)

          %{
            "mtime" => mtime_str,
            "members" => members_list,
            "reachables" => reachables_list,
            "mapping" => mapping_map
          } = cache_entry

          mtime = string_to_mtime(mtime_str)

          members = MapSet.new(members_list)
          reachables = MapSet.new(reachables_list)

          mapping =
            Map.new(mapping_map, fn {member_as_str, reachables_list} ->
              member_as = String.to_integer(member_as_str)
              {member_as, MapSet.new(reachables_list)}
            end)

          result = %{members: members, reachables: reachables, mapping: mapping}

          # Re-validate file still exists and hasn't changed
          case File.stat(file_path) do
            {:ok, %File.Stat{mtime: current_mtime}} ->
              if mtime_matches?(current_mtime, mtime) do
                {:hit, result}
              else
                # File was modified since cache
                File.rm(cache_file)
                :miss
              end

            {:error, _} ->
              # File doesn't exist, remove cache
              File.rm(cache_file)
              :miss
          end
        rescue
          _e ->
            # Failed to parse cache file
            File.rm(cache_file)
            :miss
        end

      {:error, _} ->
        IO.puts("Cache miss for #{file_path} (RRC: #{rrc}, IP Version: #{ip_version}, origin_asn: #{origin_asn})")
        # Cache file doesn't exist
        :miss
    end
  end



  defp store_cache(file_path, result, rrc, origin_asn, ip_version) do
    IO.puts("Storing cache for #{file_path} (RRC: #{rrc}, IP Version: #{ip_version}, origin_asn: #{origin_asn})")
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        persist_cache_to_disk(file_path, mtime, result, rrc, origin_asn, ip_version)

      {:error, _} ->
        # Don't cache if we can't stat the file
        :ok
    end
  end
  
  def get_cache_file_path(date_str, time_str, rrc, origin_asn, ip_version) do
    if origin_asn do
      "#{@cache_dir}/#{rrc}/#{ip_version}/#{origin_asn}/bview_cache.#{date_str}.#{time_str}.json"
    else
      "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{date_str}.#{time_str}.json"
    end
  end
  
  def get_cache_file_path(file_path, rrc, origin_asn, ip_version) do
    # Extract date and time from path like "data/rrc15/output_bview.20260101.0000.txt"
    case Path.basename(file_path) do
      "output_bview." <> rest ->
        # rest is like "20260101.0000.txt"
        parts = String.split(rest, ".")
        case parts do
          [date_str, time_str, "txt"] ->
            
            get_cache_file_path(date_str, time_str, rrc, origin_asn, ip_version)
          _ ->
            if origin_asn do
              "#{@cache_dir}/#{rrc}/#{ip_version}/#{origin_asn}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
            else
              "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
            end
        end

      _ -> 
        # Fallback for unexpected file names
        if origin_asn do
          "#{@cache_dir}/#{rrc}/#{ip_version}/#{origin_asn}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
        else
          "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
        end
    end 
  end

  # Persist cache for specific file to JSON
  defp persist_cache_to_disk(file_path, mtime, result, rrc, origin_asn, ip_version) do
    try do
      File.mkdir_p(@cache_dir)
      File.mkdir_p(@cache_dir <> "/" <> rrc)
      File.mkdir_p(@cache_dir <> "/" <> rrc <> "/" <> ip_version)
      if origin_asn do
        File.mkdir_p(@cache_dir <> "/" <> rrc <> "/" <> ip_version <> "/" <> origin_asn)
      end
      cache_file = get_cache_file_path(file_path, rrc, origin_asn, ip_version)
      IO.puts("Persisting cache to disk at #{cache_file}")

      %{members: members, reachables: reachables, mapping: mapping} = result
 
      mtime_str = mtime_to_string(mtime)

      cache_entry = %{
        "mtime" => mtime_str,
        "members" => MapSet.to_list(members),
        "reachables" => MapSet.to_list(reachables),
        "mapping" =>
          Map.new(mapping, fn {member_as, reachables_set} ->
            {to_string(member_as), MapSet.to_list(reachables_set)}
          end),
          #"prefix_mapping" => Map.new(result.prefix_mapping, fn {member_as, prefixes_set} -> {to_string(member_as), MapSet.to_list(prefixes_set)} end)
      }

      File.write!(cache_file, Jason.encode!(cache_entry, pretty: true))
    rescue
      e ->
        IO.warn("Failed to persist cache to disk: #{inspect(e)}")
    end
  end


  def erase_invalid_dates do
    IO.puts("Starting validation of all bview files...")
    data_dir = "data"
    
    case File.dir?(data_dir) do
      true ->
        txt_files = find_txt_files(data_dir)
        IO.puts("Found #{Enum.count(txt_files)} .txt files to validate")
        Enum.each(txt_files, &check_and_erase_if_invalid/1)
        IO.puts("Validation complete")
        
        # Wrap the success in the expected tuple format
        {:ok, "Validation complete. Checked #{Enum.count(txt_files)} files."}
      
      false ->
        IO.warn("Data directory not found: #{data_dir}")
        
        # Return an error tuple so the controller can handle the failure gracefully
        {:error, "Data directory not found"}
    end
  end 

  # Recursively find all .txt files in a directory
  defp find_txt_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        Enum.flat_map(files, fn file ->
          path = Path.join(dir, file)
          case File.dir?(path) do
            true -> find_txt_files(path)
            false ->
              if String.ends_with?(file, ".txt") do
                [path]
              else
                []
              end
          end
        end)
      {:error, _} ->
        []
    end
  end

  defp check_and_erase_if_invalid(file_path) do
    case parse_file_path(file_path) do
      {:ok, %{date_str: date_str, time_str: time_str, rrc: rrc}} ->
        case read_first_line(file_path) do
          {:ok, first_line} ->
            case extract_timestamp(first_line) do
              {:ok, timestamp} ->
                if is_date_invalid?(date_str, timestamp) do
                  IO.puts("Invalid date detected in #{file_path}")
                  erase_invalid_file_set(file_path, date_str, time_str, rrc)
                end
              {:error, _} ->
                :ok
            end
          {:error, _} ->
            :ok
        end
      {:error, _} ->
        :ok
    end
  end

  defp parse_file_path(file_path) do
    case Path.basename(file_path) do
      "output_bview." <> rest ->
        parts = String.split(rest, ".")
        case parts do
          [date_str, time_str, "txt"] ->
            path_parts = String.split(file_path, "/")
            case path_parts do
              ["data", rrc | _] ->
                {:ok, %{date_str: date_str, time_str: time_str, rrc: rrc}}
              _ ->
                {:error, "Invalid path structure"}
            end
          _ ->
            {:error, "Invalid filename format"}
        end
      _ ->
        {:error, "Not an output_bview file"}
    end
  end

  defp read_first_line(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case String.split(content, "\n") do
          [first_line | _] ->
            {:ok, String.trim(first_line)}
          [] ->
            {:error, "Empty file"}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_timestamp(line) do
    # Format: TABLE_DUMP2|1740787200|B|...
    case String.split(line, "|") do
      [_header, timestamp_str | _] ->
        case Integer.parse(timestamp_str) do
          {timestamp, _} ->
            {:ok, timestamp}
          :error ->
            {:error, "Invalid timestamp"}
        end
      _ ->
        {:error, "Invalid line format"}
    end
  end

  defp is_date_invalid?(date_str, timestamp) do
    case parse_date_string(date_str) do
      {:ok, filename_date} ->
        case unix_timestamp_to_date(timestamp) do
          {:ok, timestamp_date} ->
            diff = Date.diff(timestamp_date, filename_date)
            abs(diff) >= 7
          {:error, _} ->
            false
        end
      {:error, _} ->
        false
    end
  end

  defp parse_date_string(date_str) when byte_size(date_str) == 8 do
    year_str = String.slice(date_str, 0..3)
    month_str = String.slice(date_str, 4..5)
    day_str = String.slice(date_str, 6..7)
    
    with {year, ""} <- Integer.parse(year_str),
         {month, ""} <- Integer.parse(month_str),
         {day, ""} <- Integer.parse(day_str),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _ -> {:error, "Invalid date format"}
    end
  end

  defp parse_date_string(_), do: {:error, "Invalid date format"}

  defp unix_timestamp_to_date(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, dt} ->
        {:ok, DateTime.to_date(dt)}
      :error ->
        {:error, "Invalid timestamp"}
    end
  end

  defp erase_invalid_file_set(txt_file_path, date_str, time_str, rrc) do
    # Delete the .txt file
    case File.rm(txt_file_path) do
      :ok -> IO.puts("  Deleted: #{txt_file_path}")
      {:error, reason} -> IO.warn("  Failed to delete #{txt_file_path}: #{inspect(reason)}")
    end
    
    # Delete the .gz file: data/rrc/bview.20250301.0000.gz
    gz_file = "data/#{rrc}/bview.#{date_str}.#{time_str}.gz"
    case File.rm(gz_file) do
      :ok -> IO.puts("  Deleted: #{gz_file}")
      {:error, :enoent} -> :ok  # File doesn't exist, that's fine
      {:error, reason} -> IO.warn("  Failed to delete #{gz_file}: #{inspect(reason)}")
    end
    
    # Delete cache files if they exist
    cache_v4 = "data/cache/#{rrc}/v4/bview_cache.#{date_str}.#{time_str}.json"
    case File.rm(cache_v4) do
      :ok -> IO.puts("  Deleted: #{cache_v4}")
      {:error, :enoent} -> :ok  # File doesn't exist, that's fine
      {:error, reason} -> IO.warn("  Failed to delete #{cache_v4}: #{inspect(reason)}")
    end
    
    cache_v6 = "data/cache/#{rrc}/v6/bview_cache.#{date_str}.#{time_str}.json"
    case File.rm(cache_v6) do
      :ok -> IO.puts("  Deleted: #{cache_v6}")
      {:error, :enoent} -> :ok  # File doesn't exist, that's fine
      {:error, reason} -> IO.warn("  Failed to delete #{cache_v6}: #{inspect(reason)}")
    end
  end
 
  defp mtime_to_string({{year, month, day}, {hour, min, sec}}) do
    "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}-#{String.pad_leading(Integer.to_string(day), 2, "0")}T#{String.pad_leading(Integer.to_string(hour), 2, "0")}:#{String.pad_leading(Integer.to_string(min), 2, "0")}:#{String.pad_leading(Integer.to_string(sec), 2, "0")}Z"
  end
 
  defp mtime_to_string(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end
 
  defp mtime_to_string(mtime_str) when is_binary(mtime_str) do
    mtime_str
  end
 
  defp mtime_to_string(mtime) do
    inspect(mtime)
  end
 
  defp string_to_mtime(mtime_str) when is_binary(mtime_str) do
    case DateTime.from_iso8601(mtime_str) do
      {:ok, dt, _offset} ->
        dt
      :error ->
        # Fallback: just return the string (won't match)
        mtime_str
    end
  end
 
  defp mtime_matches?({{y1, m1, d1}, {h1, min1, s1}} = _file_mtime, %DateTime{year: y2, month: m2, day: d2, hour: h2, minute: min2, second: s2}) do
    y1 == y2 and m1 == m2 and d1 == d2 and h1 == h2 and min1 == min2 and s1 == s2
  end

  defp mtime_matches?({{y1, m1, d1}, {h1, min1, s1}}, {{y2, m2, d2}, {h2, min2, s2}}) do
    y1 == y2 and m1 == m2 and d1 == d2 and h1 == h2 and min1 == min2 and s1 == s2
  end
 
  defp mtime_matches?(_file_mtime, _cache_mtime), do: false
end
