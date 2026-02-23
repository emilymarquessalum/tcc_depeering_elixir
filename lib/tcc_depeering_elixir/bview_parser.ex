defmodule TccDepeeringElixir.BViewParser do
  @moduledoc """
  Parses bgpdump TABLE_DUMP2 output and extracts:
  - Unique members (first AS in path)
  - Unique reachables (prefixes)
  - Mapping of member AS to reachable prefixes
  """

  @doc """
  Parses a bgpdump output file and returns analysis results.

  Options:
    - `:limit` - Maximum number of lines to read (default: :infinity for all lines)

  Returns:
    {:ok, %{
      members: MapSet of member ASes,
      reachables: MapSet of reachable prefixes,
      mapping: %{member_as => MapSet of reachables}
    }}

    {:error, reason} if file cannot be read
  """
  def parse_file(file_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, :infinity)

    try do
      accumulator = {MapSet.new(), MapSet.new(), %{}}

      result =
        File.stream!(file_path)
        |> stream_limit(limit)
        |> Stream.map(&String.trim/1)
        |> Stream.filter(&(String.length(&1) > 0))
        |> Enum.reduce(accumulator, &parse_line/2)

      {members, reachables, mapping} = result

      {:ok,
       %{
         members: members,
         reachables: reachables,
         mapping: mapping
       }}
    rescue
      e -> {:error, "Failed to parse file: #{inspect(e)}"}
    end
  end

  @doc """
  Get statistics about the parsed data.
  """
  def stats(result) do
    %{
      members: members,
      reachables: reachables,
      mapping: mapping
    } = result

    total_announcements =
      mapping
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()
 
    %{
      unique_members_count: MapSet.size(members),
      unique_reachables_count: MapSet.size(reachables),
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

  defp parse_line(line, {members, reachables, mapping}) do
    fields = String.split(line, "|")

    if length(fields) >= 9 do
      prefix = Enum.at(fields, 5)
      as_path_str = Enum.at(fields, 6)
     

      as_path =
        as_path_str
        |> String.split()
        |> Enum.map(&parse_asn/1)
        |> Enum.reject(&is_nil/1)

      # I still want to map that
      #if length(as_path) == 1 do
      #  No member->reachable
      #  {members, reachables, mapping}
      
      reachable = List.last(as_path)
      case as_path do
        [member_as | _] -> # get the first item and do with it...
          new_members = MapSet.put(members, member_as)
          new_reachables = MapSet.put(reachables, reachable)

          new_mapping =
            Map.update(mapping, member_as, MapSet.new([reachable]), fn reachables_set ->
              MapSet.put(reachables_set, reachable)
            end)

          {new_members, new_reachables, new_mapping}

        [] ->
          {members, reachables, mapping}
      end
    else
      {members, reachables, mapping}
    end
  end

  defp parse_asn(asn_str) do
    case Integer.parse(asn_str) do
      {asn, ""} -> asn
      _ -> nil
    end
  end
end
