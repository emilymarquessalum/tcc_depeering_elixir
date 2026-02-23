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
    IO.puts("Checking cache for #{file_path} (RRC: #{rrc}, IP Version: #{ip_version})")
    case check_cache(file_path, rrc, ip_version) do
      {:hit, result} ->
        {:ok, result, cached: true}

      :miss ->
        case TccDepeeringElixir.BViewParser.parse_file(file_path, opts) do
          {:ok, result} ->
            store_cache(file_path, result, rrc, ip_version)
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
  def clear(file_path, rrc, ip_version) do
    cache_file = get_cache_file_path(file_path, rrc, ip_version)
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

  defp check_cache(file_path, rrc, ip_version) do
    cache_file = get_cache_file_path(file_path, rrc, ip_version)
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
        IO.puts("Cache miss for #{file_path} (RRC: #{rrc})")
        # Cache file doesn't exist
        :miss
    end
  end



  defp store_cache(file_path, result, rrc, ip_version) do
    IO.puts("Storing cache for #{file_path} (RRC: #{rrc}, IP Version: #{ip_version})")
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        persist_cache_to_disk(file_path, mtime, result, rrc, ip_version)

      {:error, _} ->
        # Don't cache if we can't stat the file
        :ok
    end
  end
  
  def get_cache_file_path(date_str, time_str, rrc, ip_version) do
    "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{date_str}.#{time_str}.json"
  end
  def get_cache_file_path(file_path, rrc, ip_version) do
    # Extract date and time from path like "data/rrc15/output_bview.20260101.0000.txt"
    case Path.basename(file_path) do
      "output_bview." <> rest ->
        # rest is like "20260101.0000.txt"
        parts = String.split(rest, ".")
        case parts do
          [date_str, time_str, "txt"] ->
            
            get_cache_file_path(date_str, time_str, rrc, ip_version)
          _ ->
            # Fallback for unexpected formats
            "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
        end

      _ -> 
        # Fallback for unexpected file names
        "#{@cache_dir}/#{rrc}/#{ip_version}/bview_cache.#{:erlang.system_time(:millisecond)}.json"
    end 
  end

  # Persist cache for specific file to JSON
  defp persist_cache_to_disk(file_path, mtime, result, rrc, ip_version) do
    try do
      File.mkdir_p(@cache_dir)
      File.mkdir_p(@cache_dir <> "/" <> rrc)
      File.mkdir_p(@cache_dir <> "/" <> rrc <> "/" <> ip_version)
      cache_file = get_cache_file_path(file_path, rrc, ip_version)
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
          end)
      }

      File.write!(cache_file, Jason.encode!(cache_entry, pretty: true))
    rescue
      e ->
        IO.warn("Failed to persist cache to disk: #{inspect(e)}")
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
