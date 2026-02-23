defmodule TccDepeeringElixir.BViewDownloader do
  @moduledoc """
  Handles downloading and processing bgpdump files with caching.
  
  Checks for existing files and sizes before downloading/processing.
  """

  @min_gz_size_bytes 100 * 1024 * 1024  # 100 MB

  @doc """
  Downloads bgpdump file if needed and generates output file.
  
  Returns:
    {:ok, %{
      gz_file: path to .gz file,
      output_file: path to parsed output file,
      cached: boolean (whether files were already present)
    }}
    
    {:error, reason}
  """
  def fetch_and_process(rrc, ripe_month_dir, ripe_date, time_str, prefix, asn) do
    folder = "data/#{rrc}"
    gz_file = "#{folder}/bview.#{ripe_date}.#{time_str}.gz"
    output_file = "#{folder}/#{prefix}/output_bview.#{ripe_date}.#{time_str}.txt"
    base_url = "https://data.ris.ripe.net/#{rrc}/#{ripe_month_dir}/bview.#{ripe_date}.#{time_str}.gz"

    with :ok <- ensure_folder_exists(folder),
        :ok <- ensure_folder_exists(folder <> "/" <> prefix),
         file_status <- check_and_prepare_files(gz_file, output_file),
         :ok <- maybe_download(file_status, base_url, gz_file),
         :ok <- maybe_process(file_status, gz_file, output_file, prefix, asn) do
      cached? = file_status == :cached
      #IO.puts("Download and processing completed. Cached: #{cached?}")
      {:ok, %{gz_file: gz_file, output_file: output_file, cached: cached?}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_download(:cached, _base_url, _gz_file) do
    IO.puts("gz File already cached, skipping download.") 
    :ok
  end
  defp maybe_download(:needs_process, _base_url, _gz_file), do: :ok
  defp maybe_download(:needs_download, base_url, gz_file) do
    download_file(base_url, gz_file)
  end

  defp maybe_process(:cached, _gz_file, _output_file, _prefix, _asn) do
    IO.puts("Output file already cached, skipping processing.") 
    :ok
  end
  defp maybe_process(:needs_process, gz_file, output_file, prefix, asn) do
    process_bgpdump(gz_file, output_file, prefix, asn)
  end
  defp maybe_process(:needs_download, gz_file, output_file, prefix, asn) do
    process_bgpdump(gz_file, output_file, prefix, asn)
  end

  defp ensure_folder_exists(folder) do
    case File.mkdir_p(folder) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create folder: #{reason}"}
    end
  end

  defp check_and_prepare_files(gz_file, output_file) do
    gz_status = check_gz_file(gz_file)
    output_status = check_output_file(output_file)

    case {gz_status, output_status} do
      # Both valid - use cache
      {:valid, :exists} ->
        :cached

      # gz valid, output missing - need to process
      {:valid, :missing} ->
        :needs_process

      # gz needs download, output missing - need to download
      {:needs_download, :missing} ->
        :needs_download

      # gz needs download, output exists - clean up output and download
      {:needs_download, :exists} ->
        File.rm(output_file)
        :needs_download
    end
  end

  defp check_gz_file(gz_file) do
    case File.exists?(gz_file) do
      false ->
        :needs_download

      true ->
        case validate_gz_size(gz_file) do
          :ok -> :valid
          :error -> handle_corrupt_gz(gz_file)
        end
    end
  end

  defp check_output_file(output_file) do
    case File.exists?(output_file) do
      true -> :exists
      false -> :missing
    end
  end

  defp validate_gz_size(gz_file) do
    case File.stat(gz_file) do
      {:ok, %File.Stat{size: size}} when size >= @min_gz_size_bytes ->
        :ok

      {:ok, %File.Stat{size: size}} ->
        {:error, "File too small: #{size} bytes (min #{@min_gz_size_bytes})"}

      {:error, reason} ->
        {:error, "Failed to stat file: #{reason}"}
    end
  end

  defp handle_corrupt_gz(gz_file) do
    File.rm(gz_file)
    :needs_download
  end

  defp download_file(base_url, destination) do
    try do
      :inets.start()
      :ssl.start()

      destination_charlist = to_charlist(destination)
      url_charlist = to_charlist(base_url)

      case :httpc.request(:get, {url_charlist, []}, [], [stream: destination_charlist]) do
        {:ok, :saved_to_file} ->
          case validate_gz_size(destination) do
            :ok -> :ok
            {:error, reason} -> {:error, "Downloaded file validation failed: #{reason}"}
          end

        {:error, reason} ->
          {:error, "Download failed: #{reason}"}
      end
    rescue
      e ->
        {:error, "Download error: #{inspect(e)}"}
    end
  end

  defp process_bgpdump(gz_file, output_file, prefix, asn) do
    try do
      command =
        "bgpdump -m \"#{gz_file}\" | fgrep --line-buffered \"|#{prefix}|#{asn}|\" > #{output_file}"
      IO.puts("Processing with command: #{command}")
      case System.cmd("sh", ["-c", command]) do
        {_output, 0} ->
          :ok
        IO.puts("bgpdump finished")
        {output, exit_code} ->
          {:error, "bgpdump failed with exit code #{exit_code}: #{output}"}
      end
    rescue
      e ->
        {:error, "bgpdump execution error: #{inspect(e)}"}
    end
  end
end
