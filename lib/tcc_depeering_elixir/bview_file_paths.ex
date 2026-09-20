defmodule TccDepeeringElixir.BViewFilePaths do
  @moduledoc """
  Centralized builder/parser for bview-related file paths.

  Conventions:
  - .gz files are keyed only by collector/date/time
  - .txt and .json files optionally include origin_asn in filename
  """

  @data_dir "data"
  @cache_dir Path.join(@data_dir, "cache")

  def data_dir, do: @data_dir
  def cache_dir, do: @cache_dir

  def collector_dir(rrc), do: Path.join(@data_dir, to_string(rrc))

  def output_dir(rrc, prefix), do: Path.join(collector_dir(rrc), to_string(prefix))

  def gz_file(rrc, date_input, time_input) do
    date_str = normalize_date(date_input)
    time_str = normalize_time(time_input)
    Path.join(collector_dir(rrc), "bview.#{date_str}.#{time_str}.gz")
  end

  def output_txt_file(rrc, prefix, date_input, time_input, origin_asn \\ nil, ip_version \\ "v4") do
    date_str = normalize_date(date_input)
    time_str = normalize_time(time_input)
    Path.join(output_dir(rrc, prefix), output_txt_filename(date_str, time_str, origin_asn, ip_version))
  end

  def cache_json_file(rrc, ip_version, date_input, time_input, origin_asn \\ nil) do
    date_str = normalize_date(date_input)
    time_str = normalize_time(time_input)
    Path.join(cache_dir_for(rrc, ip_version), cache_json_filename(date_str, time_str, origin_asn))
  end

  def cache_dir_for(rrc, ip_version) do
    Path.join([@cache_dir, to_string(rrc), to_string(ip_version)])
  end

  def output_txt_filename(date_str, time_str, origin_asn \\ nil, ip_version \\ "v4") do
    "output_bview.#{date_str}.#{time_str}.#{ip_version}#{origin_suffix(origin_asn)}.txt"
  end

  def cache_json_filename(date_str, time_str, origin_asn \\ nil) do
    "bview_cache.#{date_str}.#{time_str}#{origin_suffix(origin_asn)}.json"
  end

  def parse_output_txt_file(file_path_or_name) do
    file_name = Path.basename(file_path_or_name)

    case Regex.run(~r/^output_bview\.(\d{8})\.(\d{4})\.(v4|v6)(?:\.origin_as\.([^\.]+))?\.txt$/, file_name) do
      [_, date_str, time_str, ip_version] ->
        {:ok, %{date_str: date_str, time_str: time_str, ip_version: ip_version, origin_asn: nil}}

      [_, date_str, time_str, ip_version, origin_asn] ->
        {:ok, %{date_str: date_str, time_str: time_str, ip_version: ip_version, origin_asn: origin_asn}}

      _ ->
        {:error, "Invalid output_bview filename format"}
    end
  end

  def normalize_date(%Date{} = date) do
    date
    |> Date.to_string()
    |> String.replace("-", "")
  end

  def normalize_date(date) when is_integer(date), do: Integer.to_string(date)

  def normalize_date(date) when is_binary(date), do: date

  def normalize_time(time) when is_integer(time) and time >= 0 and time <= 23 do
    String.pad_leading(Integer.to_string(time), 2, "0") <> "00"
  end

  def normalize_time(time) when is_integer(time), do: Integer.to_string(time)

  def normalize_time(time) when is_binary(time) and byte_size(time) == 2 do
    time <> "00"
  end

  def normalize_time(time) when is_binary(time), do: time

  defp origin_suffix(origin_asn) when origin_asn in [nil, ""], do: ""
  defp origin_suffix(origin_asn), do: ".origin_as.#{origin_asn}"
end