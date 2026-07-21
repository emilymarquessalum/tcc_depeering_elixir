defmodule TccDepeeringElixir.BViewParser do
  @moduledoc """
  Parses bgpdump TABLE_DUMP2 output and extracts data optimally.
  """

  def parse_file(file_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, :infinity)

    try do
      IO.inspect("Starting parse for #{file_path}", label: "DEBUG")
      accumulator = {MapSet.new(), MapSet.new(), MapSet.new(), %{}}

       
      result =
        file_path
        |> File.stream!(read_ahead: 100_000)  
        |> stream_limit(limit)
        |> Enum.reduce(accumulator, &parse_line/2)

      {members, reachables, transit_ases, mapping} = result

      {:ok,
       %{
         members: members,
         reachables: reachables,
         transit_ases: transit_ases,
         mapping: mapping
       }}
    rescue
      e ->
        IO.inspect(e, label: "ERROR in parse_file")
        {:error, "Failed to parse file: #{inspect(e)}"}
    end
  end

  # currently unused but could be helpful in the future.
  def stats(result) do
    %{
      members: members,
      reachables: reachables, 
      transit_ases: transit_ases,
      mapping: mapping
    } = result
 
    total_announcements =
      Enum.reduce(mapping, 0, fn {_as, reachables_set}, acc -> 
        acc + MapSet.size(reachables_set)
      end)
 
    %{
      unique_members_count: MapSet.size(members),
      unique_reachables_count: MapSet.size(reachables),
      unique_transit_ases_count: MapSet.size(transit_ases),
      total_member_mappings: map_size(mapping),
      total_announcements: total_announcements,
      
      top_members:
        mapping
        |> Enum.sort_by(fn {_as, reachables_set} -> MapSet.size(reachables_set) end, :desc)
        |> Enum.take(10)
        |> Enum.map(fn {member_as, reachables_set} ->
          {member_as, MapSet.size(reachables_set)}
        end)
    }
  end

  defp stream_limit(stream, :infinity), do: stream
  defp stream_limit(stream, limit), do: Stream.take(stream, limit)

  defp parse_line(line, acc) do
    
    case String.trim_trailing(line) do
      "" -> acc
      trimmed_line -> process_fields(String.split(trimmed_line, "|"), acc)
    end
  end

 
  defp process_fields([_, _, _, _, ixp_asn_str, prefix, as_path_str, _, communities | _], {members, reachables, transit_ases, mapping}) do
    ixp_asn = parse_asn(ixp_asn_str)
 
    as_path_str
    |> String.split(" ", trim: true)
    |> process_as_path(ixp_asn, [], nil)
    |> case do
      {[], _} -> 
        {members, reachables, transit_ases, mapping}

      {as_path, reachable} ->
        [member_as | _] = as_path
        
        new_members = MapSet.put(members, member_as)

        {new_reachables, new_transit_ases} =
          if member_as == reachable do
            {reachables, MapSet.put(transit_ases, member_as)}
          else
            {MapSet.put(reachables, reachable), transit_ases}
          end

        reachable_entry = %{
          reachable: reachable, 
          as_path: as_path,
          prefix: prefix,
          communities: communities
        }  

        new_mapping =
          Map.update(mapping, member_as, MapSet.new([reachable_entry]), fn reachables_set ->
            MapSet.put(reachables_set, reachable_entry)
          end)

        {new_members, new_reachables, new_transit_ases, new_mapping}
    end
  end

  # Fallback for malformed lines (less than 9 elements)
  defp process_fields(_, acc), do: acc 

  # Custom single-pass AS Path processor to replace List.last + Enum.filter + Enum.map
  defp process_as_path([], _ixp_asn, [], _last_valid), do: {[], nil}
  defp process_as_path([], _ixp_asn, acc, last_valid), do: {Enum.reverse(acc), last_valid}
  defp process_as_path([raw_asn | rest], ixp_asn, acc, last_valid) do
    case Integer.parse(raw_asn) do
      {asn, ""} when asn != ixp_asn -> 
        process_as_path(rest, ixp_asn, [asn | acc], asn)
      _ -> 
        process_as_path(rest, ixp_asn, acc, last_valid)
    end
  end

  defp parse_asn(asn_str) do
    case Integer.parse(asn_str) do
      {asn, ""} -> asn
      _ -> nil
    end
  end
end