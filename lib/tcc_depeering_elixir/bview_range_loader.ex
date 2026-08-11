defmodule TccDepeeringElixir.BViewRangeLoader do
  @moduledoc """
  Loads and processes multiple bgpdump files across a date/time range.
  
  Supports iteration by day_delta and/or time_delta.
  """

  @doc """
  Load all files in a date/time range.
  
  Options:
    - `:day_delta` - Days to add per iteration (default: 1)
    - `:time_delta` - Hours to add per iteration (default: 0)
    - `:rrc` - RRC collector name (default: "rrc15")
    - `:asn` - Monitor AS number (default: "26162", IX.br São Paulo AS Monitor)
    - `:prefix` - Monitor prefix (default: "187.16.216.253")
    - `:concurrency` - Number of concurrent snapshots to load (default: 2)
  
  Returns:
    {:ok, [%{date: ..., time: ..., file: ..., result: ...}, ...]}
    {:error, reason}
  """
  def load_range(start_date, end_date, time_str, opts \\ []) do
    day_delta = Keyword.get(opts, :day_delta, 1) 
    time_delta = Keyword.get(opts, :time_delta, 0)
    rrc = Keyword.get(opts, :rrc, "")
    asn = Keyword.get(opts, :asn, "")
    origin_asn = Keyword.get(opts, :origin_asn, nil)
    prefix = Keyword.get(opts, :prefix, "187.16.216.253")
    concurrency = Keyword.get(opts, :concurrency, 2)
    ip_version = Keyword.get(opts, :ip_version, "v4")  
 
    start_date = parse_date(start_date)
    end_date = parse_date(end_date)

    if Date.compare(start_date, end_date) == :gt do
      {:error, "start_date must be before end_date"}
    else
      results = iterate_range(start_date, end_date, day_delta, time_delta, rrc, asn, prefix, origin_asn, concurrency, [], time_str, ip_version)
      {:ok, results}
    end
  end

  defp parse_date(date) when is_binary(date) do 
    case Date.from_iso8601(date) do
      {:ok, parsed_date} -> parsed_date
      :error -> raise "Invalid date format: #{date}. Use YYYY-MM-DD"
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp iterate_range(current_date, end_date, day_delta, time_delta, rrc, asn, prefix, origin_asn, concurrency, acc, time_str, ip_version) do
    # If day_delta is 0, only iterate once (time_delta will handle day progression)
    if day_delta == 0 do
      case fetch_times_for_date_async(current_date, end_date, time_delta, rrc, asn, prefix, origin_asn, concurrency, ip_version) do
        {:stop_iteration, day_results} ->
          IO.puts("[iterate_range] Stopping iteration due to empty result")
          Enum.reverse(acc ++ day_results)
        day_results ->
          Enum.reverse(acc ++ day_results)
      end
    else
      # Normal day iteration when day_delta > 0
      if Date.compare(current_date, end_date) == :gt do
        Enum.reverse(acc)
      else
        case fetch_times_for_date_async(current_date, current_date, time_delta, rrc, asn, prefix, origin_asn, concurrency, ip_version) do
          {:stop_iteration, day_results} ->
            IO.puts("[iterate_range] Stopping iteration due to empty result")
            Enum.reverse(acc ++ day_results)
          day_results ->
            acc = acc ++ day_results
            # Move to next date
            next_date = Date.add(current_date, day_delta)
            iterate_range(next_date, end_date, day_delta, time_delta, rrc, asn, prefix, origin_asn, concurrency, acc, time_str, ip_version)
        end
      end
    end 
  end 
 
  defp fetch_times_for_date_async(date, limit_date, time_delta, rrc, asn, prefix, origin_asn, concurrency, ip_version) do
    hours_with_days =
      generate_date_hour_pairs(date, limit_date, time_delta)
      |> Enum.map(fn {current_date, hour} -> {current_date, hour, rrc, asn, prefix, origin_asn, ip_version} end)

    # Separate cached and non-cached items
    # Cache will only be in one thread (it only needs to load a file...), 
    # while non-cached can be processed in parallel (run more than one bgpdump at a time)
    {cached_items, non_cached_items} = partition_by_cache_status(hours_with_days)

    IO.puts("Cache status: #{length(cached_items)} cached, #{length(non_cached_items)} to download")

    Enum.each(cached_items, fn {d, h, _, _, _, _, ip_version} -> 
      IO.puts("  ✓ #{Date.to_string(d)} #{String.pad_leading(Integer.to_string(h), 2, "0")}:00 (cached) IP Version: #{ip_version}")
    end)

    Enum.each(non_cached_items, fn {d, h, _, _, _, _, ip_version} -> 
      IO.puts("  - #{Date.to_string(d)} #{String.pad_leading(Integer.to_string(h), 2, "0")}:00 (will download) IP Version: #{ip_version}")
    end)

    
    non_cached_results =
      non_cached_items
      |> Task.async_stream( 
        fn {date, hour, rrc, asn, prefix, origin_asn, ip_version} ->
          IO.puts("[task] Processing #{Date.to_string(date)} #{String.pad_leading(Integer.to_string(hour), 2, "0")}:00 IP Version: #{ip_version}")
          fetch_single_file(date, hour, rrc, asn, prefix, origin_asn, ip_version) 
        end,
        max_concurrency: concurrency,
        timeout: 25_000_000  
        )
      |> Enum.map(fn
        {:ok, result} -> {:ok, result}
        {:exit, reason} -> 
          IO.puts("[task-error] Task exited with reason: #{inspect(reason)}")
          {:error, reason}
      end)

      
    cached_results =
      cached_items
      |> Task.async_stream(
        fn {date, hour, rrc, asn, prefix, origin_asn, ip_version} ->
          IO.puts("[task-cached] Processing #{Date.to_string(date)} #{String.pad_leading(Integer.to_string(hour), 2, "0")}:00 IP Version: #{ip_version}")
          fetch_single_file(date, hour, rrc, asn, prefix, origin_asn, ip_version)
        end,
        max_concurrency: 1,
        timeout: 5_000_000   
        )
      |> Enum.map(fn
        {:ok, result} -> {:ok, result}
        {:exit, reason} -> 
          IO.puts("[task-error] Cached task exited with reason: #{inspect(reason)}")
          {:error, reason}
      end)

    # Separate successes and errors
    all_results = non_cached_results ++ cached_results
    successful_results = Enum.filter(all_results, fn
      {:ok, _} -> true
      {:error, _} -> false
      :stop_iteration -> true
    end) |> Enum.map(fn
      {:ok, result} -> result
      :stop_iteration -> :stop_iteration
    end)
    
    error_count = length(all_results) - length(successful_results) 
    
    if error_count > 0 do
      IO.puts("[fetch_times_for_date_async] Completed #{length(successful_results)} results, and #{error_count} raised errors")
    else
      IO.puts("[fetch_times_for_date_async] Completed #{length(successful_results)} results")
    end
    
    # Check if any result signaled to stop iteration
    case Enum.find(successful_results, fn result -> result == :stop_iteration end) do
      :stop_iteration ->
        {:stop_iteration, Enum.filter(successful_results, fn result -> result != :stop_iteration end)}
      nil ->
        successful_results
    end
  end

  # Check which items have cache files and partition them
  defp partition_by_cache_status(hours_with_days) do
    Enum.partition(hours_with_days, fn {date, hour, rrc, _asn, _prefix, origin_asn, ip_version} ->
      cache_file = TccDepeeringElixir.BViewFilePaths.cache_json_file(rrc, ip_version, date, hour, origin_asn)
      File.exists?(cache_file)
    end)
  end
 

  @doc """
  Generate all (date, hour) pairs from start_date to end_date with time_delta increments.
  
  Handles hour wrapping across days. For example, with time_delta=8:
  - 0 hours → {start_date, 0}
  - 8 hours → {start_date, 8}
  - 16 hours → {start_date, 16}
  - 24 hours → {start_date + 1 day, 0}
  - 32 hours → {start_date + 1 day, 8}
  
  When time_delta=0, returns a single pair {start_date, 0}.
  """
  def generate_date_hour_pairs(start_date, end_date, time_delta) do
    # When time_delta is 0, no time increment needed (used with day_delta iteration)
    if time_delta == 0 do
      if Date.compare(start_date, end_date) != :gt do
        [{start_date, 0}]
      else
        []
      end
    else
      # Generate all (date, hour) pairs from start_date to end_date
      # Handles hour wrapping across days
      Stream.iterate(0, &(&1 + time_delta))
      |> Stream.map(fn total_hours ->
        days_passed = div(total_hours, 24)
        hour = rem(total_hours, 24)
        current_date = Date.add(start_date, days_passed)
        {current_date, hour}
      end)
      |> Stream.take_while(fn {current_date, _hour} -> 
        Date.compare(current_date, end_date) != :gt
      end)
      |> Enum.to_list()
    end
  end

  # Uses the fetching functions and returns the processed result for a single date/hour
  defp fetch_single_file(date, hour, rrc, asn, prefix, origin_asn, ip_version) do
    date_str = Date.to_string(date) |> String.replace("-", "")
    time_str = String.pad_leading(Integer.to_string(hour), 2, "0") <> "00"
    ripe_month_dir = "#{date.year}.#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"

    IO.puts("[fetch_single_file] Starting for #{date_str} #{time_str}")
    IO.puts("[fetch_single_file] Calling fetch_and_process with rrc=#{rrc}, month=#{ripe_month_dir}, date=#{date_str}, time=#{time_str}")

    # gets the gz and creates the .txt file
    case TccDepeeringElixir.BViewDownloader.fetch_and_process(
           rrc,
           ripe_month_dir,
           date_str,
           time_str,
           prefix,
           asn,
            origin_asn,
           ip_version
         ) do
      {:ok, %{output_file: output_file, cached: was_cached, event_id: event_id}} ->
        IO.puts("[fetch_single_file] fetch_and_process returned {:ok, ...} for #{date_str} #{time_str}")
        
        # Check if output file is empty
        case File.stat(output_file) do
          #{:ok, %File.Stat{size: 0}} -> 
          #  IO.puts("[fetch_single_file] Output file is EMPTY for #{date_str} #{time_str} - continuing to next time slot")
                         
          {:ok, _} ->
            case TccDepeeringElixir.BViewCache.parse_or_cache(output_file, rrc, ip_version: ip_version, event_id: event_id, origin_asn: origin_asn) do
              {:ok, parse_result, cached: parse_cached} ->
                IO.puts("[fetch_single_file] parse_or_cache returned {:ok, ...} for #{date_str} #{time_str}")
                
                %{
                  members: unique_members,
                  reachables: unique_reachables,
                  mapping: member_to_reachable_paths
                } = parse_result

                mapping_as_map =
                  member_to_reachable_paths
                  |> Map.new(fn {member_as, reachables_set} ->
                    {member_as, MapSet.to_list(reachables_set)}
                  end)

                result = %{
                  date: date_str,
                  time: time_str,
                  file: output_file,
                  cached: %{download: was_cached, parse: parse_cached},
                  data: %{
                    unique_members_count: MapSet.size(unique_members),
                    unique_reachables_count: MapSet.size(unique_reachables),
                    member_count: map_size(member_to_reachable_paths),
                    members: MapSet.to_list(unique_members),
                    reachables: MapSet.to_list(unique_reachables),
                    mapping: mapping_as_map
                  }
                }
                IO.puts("[fetch_single_file] Successfully returning result for #{date_str} #{time_str}")
                result

              {:error, parse_error} ->
                IO.puts("[fetch_single_file] parse_or_cache returned error: #{parse_error} for #{date_str} #{time_str}")
                %{
                  date: date_str,
                  time: time_str,
                  file: output_file,
                  status: "error",
                  message: "Parse failed: #{parse_error}"
                }
            end
          {:error, stat_error} ->
            IO.puts("[fetch_single_file] Failed to stat output file: #{stat_error}")
            %{
              date: date_str,
              time: time_str,
              status: "error",
              message: "Failed to check output file: #{stat_error}"
            }
        end

      {:error, download_error} ->
        IO.puts("[fetch_single_file] fetch_and_process returned error: #{download_error} (for date #{date_str} #{time_str})")
        
        %{
          date: date_str,
          time: time_str,
          status: "error",
          message: "Download/process failed: #{download_error}"
        }
    end
  rescue
    e ->
      IO.puts("[fetch_single_file] RESCUE caught exception for #{Date.to_string(date)} #{String.pad_leading(Integer.to_string(hour), 2, "0")}:00: #{inspect(e)}")
      IO.puts("[fetch_single_file] Exception stacktrace: #{inspect(__STACKTRACE__)}")
      %{
        date: Date.to_string(date),
        time: String.pad_leading(Integer.to_string(hour), 2, "0") <> "00",
        status: "error",
        message: "Unexpected error: #{inspect(e)}"
      }
  end
end
