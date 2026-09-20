defmodule TccDepeeringElixir.BViewDeleter do
  @moduledoc """
  Handles deletion of bview output, cache, and raw files for given date ranges.
  """

  def delete_range(start_date_str, end_date_str, opts \\ []) do
    rrc = Keyword.get(opts, :rrc, "rrc15")
    prefix = Keyword.get(opts, :prefix, "")
    origin_asn = Keyword.get(opts, :origin_asn, nil)
    ip_version = Keyword.get(opts, :ip_version, "v4")
    day_delta = Keyword.get(opts, :day_delta, 1)
    time_delta = Keyword.get(opts, :time_delta, 0)
    delete_gz = Keyword.get(opts, :delete_gz, false)

    with {:ok, start_date} <- Date.from_iso8601(start_date_str),
         {:ok, end_date} <- Date.from_iso8601(end_date_str) do
      
      if Date.compare(start_date, end_date) == :gt do
        {:error, "start_date must be before or equal to end_date"}
      else
        date_hour_pairs = generate_pairs(start_date, end_date, day_delta, time_delta)

        deleted_files =
          Enum.flat_map(date_hour_pairs, fn {date, hour} ->
            delete_single_slot(date, hour, rrc, prefix, origin_asn, ip_version, delete_gz)
          end)

        {:ok, %{count: Enum.count(deleted_files), files: deleted_files}}
      end
    else
      _ -> {:error, "Invalid date format. Use YYYY-MM-DD"}
    end
  end

  defp generate_pairs(start_date, end_date, day_delta, time_delta) do
    if day_delta == 0 do
      TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(start_date, end_date, time_delta)
    else
      # Iterate over day_delta increments
      Stream.iterate(start_date, &Date.add(&1, day_delta))
      |> Stream.take_while(&(Date.compare(&1, end_date) != :gt))
      |> Enum.flat_map(fn current_date ->
        TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(current_date, current_date, time_delta)
      end)
    end
  end

  defp delete_single_slot(date, hour, rrc, prefix, origin_asn, ip_version, delete_gz) do
    date_str = Date.to_string(date) |> String.replace("-", "")
    time_str = String.pad_leading(Integer.to_string(hour), 2, "0") <> "00"

    # 1. Output .txt file
    output_txt = TccDepeeringElixir.BViewFilePaths.output_txt_file(
      rrc, prefix, date_str, time_str, origin_asn, ip_version
    )

    # 2. Parsed .json cache file
    cache_json = TccDepeeringElixir.BViewFilePaths.cache_json_file(
      rrc, ip_version, date_str, time_str, origin_asn
    )

    files_to_remove = [output_txt, cache_json]

    # 3. Optional raw .gz archive file
    files_to_remove =
      if delete_gz do
        gz_file = TccDepeeringElixir.BViewFilePaths.gz_file(rrc, date_str, time_str)
        files_to_remove ++ [gz_file]
      else
        files_to_remove
      end

    Enum.reduce(files_to_remove, [], fn file_path, acc ->
      case File.rm(file_path) do
        :ok -> [file_path | acc]
        {:error, :enoent} -> acc # File didn't exist
        {:error, reason} ->
          IO.warn("Failed to delete file #{file_path}: #{inspect(reason)}")
          acc
      end
    end)
  end
end