#!/usr/bin/env elixir

# This file was made as a test. Parse bgpdump output and extract unique members/reachables with mapping
file_path = "/home/emily/Desktop/projects/furg/tcc_depeering_elixir/data/rrc15/output_bview.20260101.0000.txt"

# Accumulator: {unique_members, unique_reachables, member_to_reachables_map}
accumulator = {MapSet.new(), MapSet.new(), %{}}

result = 
  File.stream!(file_path)
  |> Stream.take(10000)  # Read only first 10000 lines for now
  |> Stream.map(&String.trim/1) # Remove leading/trailing whitespace
  |> Stream.filter(&(String.length(&1) > 0)) # Skip empty lines
  |> Enum.reduce(accumulator, fn line, {members, reachables, mapping} ->
    fields = String.split(line, "|")
    
    # TABLE_DUMP2 format: check if we have enough fields
    if length(fields) >= 9 do
      prefix = Enum.at(fields, 5)
      as_path_str = Enum.at(fields, 6)
      
      # Parse AS path (space-separated)
      as_path = as_path_str |> String.split() |> Enum.map(&String.to_integer/1) |> Enum.reject(&is_nil/1)
      
      # Member is the first AS in the path
      case as_path do
        [member_as | _] ->
          # Update members set
          new_members = MapSet.put(members, member_as)
          # Update reachables set
          new_reachables = MapSet.put(reachables, prefix)
          # Update mapping: member -> set of reachables
          new_mapping = Map.update(mapping, member_as, MapSet.new([prefix]), fn reachables_set ->
            MapSet.put(reachables_set, prefix)
          end)
          
          {new_members, new_reachables, new_mapping}
        
        [] ->
          {members, reachables, mapping}
      end
    else
      {members, reachables, mapping}
    end
  end)

{members, reachables, mapping} = result

IO.puts("=== BGP DUMP ANALYSIS ===")
IO.puts("Unique Members (first AS in path): #{MapSet.size(members)}")
IO.puts("Unique Reachables (prefixes): #{MapSet.size(reachables)}")
IO.puts("\nMember -> Reachable mapping:")
IO.puts("Total members with mappings: #{map_size(mapping)}")

# Show first 10 members and their reachables count
mapping
|> Enum.sort_by(fn {_as, reachables_set} -> MapSet.size(reachables_set) end, :desc)
|> Enum.take(10)
|> Enum.each(fn {member_as, reachables_set} ->
  IO.puts("  AS#{member_as}: #{MapSet.size(reachables_set)} reachables")
end)

# Stats
total_reachable_count = mapping |> Map.values() |> Enum.map(&MapSet.size/1) |> Enum.sum()
IO.puts("\nTotal reachable announcements: #{total_reachable_count}")
