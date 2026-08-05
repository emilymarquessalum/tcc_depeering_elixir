defmodule TccDepeeringElixir.BViewDownloader do
  @moduledoc """
  Handles downloading and processing bgpdump files with caching.
  
  Checks for existing files and sizes before downloading/processing.
  """

  @min_file_size_bytes 1000# just so it isnt empty. Before I had a bigger restriction but 
  # some IXPs simply have small RIBs and I still should support them. What I could implement later
  # is a kind of "anomaly" detection where if the downloaded file is muuuch smaller than others that
  # exist already then I consider it an error (even then there should be a flag to let it allow it).

  def fetch_and_process(rrc, ripe_month_dir, ripe_date, time_str, prefix, asn, origin_asn, ip_version \\ "v4") do
    folder = "data/#{rrc}"
    output_file = "#{folder}/#{prefix}/output_bview.#{ripe_date}.#{time_str}.txt"
    
    # Core logic: Routeviews uses .bz2 sources, RIPE uses .gz sources.
    # However, we want our local cached file to ALWAYS be .gz for bgpdump consistency.
    is_ripe = String.starts_with?(rrc, "rrc")
    
    local_gz_file = "#{folder}/bview.#{ripe_date}.#{time_str}.gz"
    
    year = String.slice(ripe_date, 0..3)
    month = String.slice(ripe_date, 4..5)
    base_url = if is_ripe do
      "https://data.ris.ripe.net/#{rrc}/#{ripe_month_dir}/bview.#{ripe_date}.#{time_str}.gz"
    else
      # list of available routeviews: https://archive.routeviews.org
      
      "https://archive.routeviews.org/#{rrc}/bgpdata/#{year}.#{month}/RIBS/rib.#{ripe_date}.#{time_str}.bz2"
    end
     
    # Start tracking this event
    event_id = TccDepeeringElixir.BViewEventPersistence.start_event(
      rrc, ripe_month_dir, ripe_date, time_str, prefix, asn, origin_asn, ip_version
    )

    with :ok <- ensure_folder_exists(folder), 
         :ok <- ensure_folder_exists(folder <> "/" <> prefix),
         file_status <- check_and_prepare_files(local_gz_file, output_file),
         :ok <- maybe_download(file_status, base_url, local_gz_file, is_ripe, event_id),
         :ok <- maybe_process(file_status, local_gz_file, output_file, prefix, asn, origin_asn, event_id) do
      cached? = file_status == :cached
      {:ok, %{gz_file: local_gz_file, output_file: output_file, cached: cached?, event_id: event_id}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_download(:cached, _base_url, _local_gz_file, _is_ripe, _event_id) do
    IO.puts("File already cached, skipping download.") 
    :ok
  end

  defp maybe_download(:needs_process, _base_url, _local_gz_file, _is_ripe, _event_id) do
    IO.puts("Target file exists but output missing, skipping download and proceeding to processing.")
    :ok
  end

  defp maybe_download(:needs_download, base_url, local_gz_file, is_ripe, event_id) do
    TccDepeeringElixir.BViewEventPersistence.update_event_state(event_id, "downloading")
    IO.puts("Downloading file from #{base_url}")
    download_file(base_url, local_gz_file, is_ripe)
  end

  defp maybe_process(:cached, _local_gz_file, _output_file, _prefix, _asn, _origin_asn, _event_id) do
    IO.puts("Output file already cached, skipping processing.") 
    :ok
  end
  defp maybe_process(:needs_process, local_gz_file, output_file, prefix, asn, origin_asn, event_id) do
    TccDepeeringElixir.BViewEventPersistence.update_event_state(event_id, "processing")
    process_bgpdump(local_gz_file, output_file, prefix, asn, origin_asn)
  end
  defp maybe_process(:needs_download, local_gz_file, output_file, prefix, asn, origin_asn, event_id) do
    TccDepeeringElixir.BViewEventPersistence.update_event_state(event_id, "processing")
    process_bgpdump(local_gz_file, output_file, prefix, asn, origin_asn)
  end

  defp ensure_folder_exists(folder) do
    case File.mkdir_p(folder) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create folder: #{reason}"}
    end
  end

  defp check_and_prepare_files(local_gz_file, output_file) do
    gz_status = check_gz_file(local_gz_file)
    output_status = check_output_file(output_file)

    case {gz_status, output_status} do
      {:valid, :exists} -> :cached
      {:valid, :missing} -> :needs_process
      {:needs_download, :missing} -> :needs_download
      {:needs_download, :exists} ->
        File.rm(output_file)
        :needs_download
    end
  end

  defp check_gz_file(local_gz_file) do
    case File.exists?(local_gz_file) do
      false ->
        IO.puts("Target file does not exist: #{local_gz_file}")
        :needs_download
      true ->
        case validate_file_size(local_gz_file) do
          :ok -> :valid
          {:error, _reason} -> handle_corrupt_file(local_gz_file)
        end
    end
  end

  defp check_output_file(output_file) do
    case File.exists?(output_file) do
      true -> :exists
      false -> :missing
    end
  end

  defp validate_file_size(file) do
    case File.stat(file) do
      {:ok, %File.Stat{size: size}} when size >= @min_file_size_bytes ->
        :ok
      {:ok, %File.Stat{size: size}} ->
        {:error, "File too small: #{size} bytes (min #{@min_file_size_bytes})"}
      {:error, reason} ->
        {:error, "Failed to stat file: #{reason}"}
    end
  end

  defp handle_corrupt_file(file) do
    IO.puts("File is corrupt or too small: #{file}")
    File.rm(file)
    :needs_download 
  end

  defp download_file(base_url, local_gz_file, is_ripe, retries \\ 3) do
    temp_destination = if is_ripe do
      String.replace(local_gz_file, ".gz", ".temp.gz")
    else
      String.replace(local_gz_file, ".gz", ".temp.bz2")
    end
    
    try do
      :inets.start() 
      :ssl.start()

      destination_charlist = to_charlist(temp_destination)
      url_charlist = to_charlist(base_url)
      
      IO.puts("Starting download from #{base_url} to #{temp_destination} (Attempts remaining: #{retries})")
      
      case :httpc.request(:get, {url_charlist, []}, [], [stream: destination_charlist]) do
        {:ok, :saved_to_file} ->
          case validate_file_size(temp_destination) do
            :ok -> 
              handle_post_download(temp_destination, local_gz_file, is_ripe)

            {:error, reason} -> 
              File.rm(temp_destination)
              # Validation failure usually means a bad file, not a network hiccup, 
              # but we will pass it to the retry handler just in case it was a partial download.
              maybe_retry(reason, base_url, local_gz_file, is_ripe, retries)
          end

        {:error, reason} ->
          File.rm(temp_destination)
          maybe_retry(reason, base_url, local_gz_file, is_ripe, retries)
      end
    rescue
      e ->
        File.rm(temp_destination)
        maybe_retry(e, base_url, local_gz_file, is_ripe, retries)
    end
  end

  # Helper function to handle the retry logic
  defp maybe_retry(reason, base_url, local_gz_file, is_ripe, retries) when retries > 1 do
    wait_time = 5000 # 5 seconds
    IO.puts("Download failed due to #{inspect(reason)}. Retrying in #{wait_time / 1000} seconds...")
    Process.sleep(wait_time)
    
    # Recursively call download_file with one less retry available
    download_file(base_url, local_gz_file, is_ripe, retries - 1)
  end

  defp maybe_retry(final_reason, _base_url, _local_gz_file, _is_ripe, _retries) do
    # No retries left, return the final error
    {:error, "Download failed after multiple attempts. Last error: #{inspect(final_reason)}"}
  end

  defp handle_post_download(temp_destination, local_gz_file, false) do
    IO.puts("Decompressing temporary bz2 file...")
    case System.cmd("bunzip2", [temp_destination]) do
      {_, 0} ->  
        extracted_temp = String.replace(temp_destination, ".temp.bz2", ".temp")
        
        IO.puts("Re-compressing file to gzip format...")
        case System.cmd("gzip", [extracted_temp]) do
          {_, 0} ->
            gzipped_temp = extracted_temp <> ".gz"
            
            case File.rename(gzipped_temp, local_gz_file) do
              :ok -> :ok
              {:error, reason} -> {:error, "Failed renaming to final gz destination: #{inspect(reason)}"}
            end
          {output, exit_code} ->
            File.rm(extracted_temp)
            {:error, "gzip failed with exit code #{exit_code}: #{String.trim(output)}"}
        end

      {output, exit_code} ->
        File.rm(temp_destination)
        {:error, "bunzip2 failed with exit code #{exit_code}: #{String.trim(output)}"}
    end
  end

  defp handle_post_download(temp_destination, local_gz_file, true) do
    case File.rename(temp_destination, local_gz_file) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to rename final file: #{inspect(reason)}"}
    end
  end

  defp process_bgpdump(gz_file, output_file, prefix, asn, origin_asn) do
    temp_file = "#{output_file}.temp"
    
    try do
      used_filter = cond do 
        origin_asn && prefix != "" ->
          "| fgrep --line-buffered \"|#{prefix}|#{asn}|\" | awk -F'|' '$7 ~ / #{origin_asn}$/ || $7 == \"#{origin_asn}\"'"
 
        origin_asn ->
          "| awk -F'|' '$7 ~ / #{origin_asn}$/ || $7 == \"#{origin_asn}\"'"
  
        true ->
          "| fgrep --line-buffered \"|#{prefix}|#{asn}|\""
      end
      # bgpdump -m gz > txt 2>&1
      command =
        "bgpdump -m \"#{gz_file}\" #{used_filter} > #{temp_file} 2>&1"
      
      IO.puts("Processing with command: #{command}")
      
      sh_path = System.find_executable("sh") || "C:/Program Files/Git/bin/sh.exe" 

      case System.cmd(sh_path, ["-c", command], stderr_to_stdout: true) do
        {_output, exit_code} when exit_code in [0, 1] ->
          if exit_code == 1 do
            IO.puts("bgpdump finished. fgrep returned exit code 1: No matching data found. Creating empty text file.")
          else
            IO.puts("bgpdump finished successfully. Matches found.")
          end
          
          case File.rename(temp_file, output_file) do
            :ok -> :ok
            {:error, reason} -> {:error, "Failed to rename temp file to #{output_file}: #{inspect(reason)}"}
          end

        {output, exit_code} ->
          File.rm(temp_file)
          {:error, "bgpdump pipeline failed with exit code #{exit_code}: #{String.trim(output)}"}
      end
    rescue
      e ->
        File.rm(temp_file)
        {:error, "bgpdump execution error: #{inspect(e)}"}
    end
  end
end 