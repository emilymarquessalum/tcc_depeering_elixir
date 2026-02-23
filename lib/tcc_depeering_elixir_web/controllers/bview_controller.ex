defmodule TccDepeeringElixirWeb.BViewController do
  use TccDepeeringElixirWeb, :controller


  def load_ixp_ids(conn, _params) do
    ixps = TccDepeeringElixir.IXPContext.list_all_ixps()
    json(conn, %{ixps: ixps})
  end

  def bview(conn, params) do
    start_time = System.monotonic_time(:millisecond)
    
    rrc = Map.get(params, "rrc", "rrc15")
    asn = Map.get(params, "asn", "26162")
    prefix = Map.get(params, "prefix", "187.16.216.253")
    time_str = Map.get(params, "time_str", "0000")
    time_delta = Map.get(params, "time_delta", "0") |> parse_int(0)
    ip_version = Map.get(params, "ip_version", "v4") 
    
    # Check if this is a range query
    result = case {Map.get(params, "start_date"), Map.get(params, "end_date")} do
      {nil, nil} ->
        # Single file query
        single_file_query(conn, rrc, asn, prefix, ip_version)

      {start_date, end_date} when is_binary(start_date) and is_binary(end_date) ->
        # Range query
        day_delta = Map.get(params, "day_delta", "1") |> parse_int(1)
        time_delta = Map.get(params, "time_delta", "0") |> parse_int(0)
        
        case TccDepeeringElixir.BViewRangeLoader.load_range(
               start_date,
               end_date,
               time_str,
               day_delta: day_delta,
               time_delta: time_delta,
               rrc: rrc,
               asn: asn,
               prefix: prefix,
                ip_version: ip_version
             ) do
          {:ok, results} ->
            {:ok, %{
              status: "success",
              message: "Loaded #{length(results)} files",
              query_type: "range",
              params: %{
                start_date: start_date,
                end_date: end_date,
                day_delta: day_delta,
                time_delta: time_delta
              },
              results: results
            }}

          {:error, error} ->
            {:ok, %{status: "error", message: "Range query failed: #{error}"}}
        end

      _ ->
        {:ok, %{
          status: "error",
          message: "For range queries, provide both start_date and end_date"
        }}
    end
    
    end_time = System.monotonic_time(:millisecond)
    elapsed_ms = end_time - start_time
    
    case result do
      {:ok, response_data} ->
        final_response = Map.put(response_data, :time_taken_ms, elapsed_ms)
        IO.puts("[BVIEW] Query completed in #{elapsed_ms}ms") 
        json(conn, %{})
        #json(conn, final_response)
    end
  end

  defp single_file_query(_conn, rrc, asn, prefix, ip_version) do
    ripe_month_dir = "2026.01"
    ripe_date = "20260101"
    time_str = "0000"

    case TccDepeeringElixir.BViewDownloader.fetch_and_process(
           rrc,
           ripe_month_dir,
           ripe_date,
           time_str,
           prefix,
           asn
         ) do
      {:ok, %{output_file: output_file, cached: was_cached}} ->
        case TccDepeeringElixir.BViewCache.parse_or_cache(output_file, rrc, ip_version: ip_version) do
          {:ok, parse_result, cached: parse_cached} ->
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

            {:ok, %{
              status: "success",
              message: if(was_cached, do: "Using cached files", else: "Downloaded and processed"),
              query_type: "single",
              cached: %{
                download: was_cached,
                parse: parse_cached
              },
              data: %{ 
                unique_members_count: MapSet.size(unique_members),
                unique_reachables_count: MapSet.size(unique_reachables),
                member_count: map_size(member_to_reachable_paths),
                members: MapSet.to_list(unique_members),
                reachables: MapSet.to_list(unique_reachables),
                mapping: mapping_as_map
              }
            }}

          {:error, parse_error} ->
            {:ok, %{status: "error", message: "Parse failed: #{parse_error}"}}
        end

      {:error, download_error} ->
        {:ok, %{status: "error", message: "Download/process failed: #{download_error}"}}
    end
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(int, _default) when is_integer(int), do: int
  defp parse_int(_, default), do: default 
end