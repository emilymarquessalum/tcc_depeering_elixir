defmodule TccDepeeringElixir.BViewRecovery do
  @moduledoc """
  Recovers and resumes incomplete bgpdump processing events on application startup.
  
  This module is responsible for:
  1. Loading all pending events from persistence
  2. Validating their state
  3. Resuming them from where they left off
  """

  require Logger

  @doc """
  Recover all incomplete events and resume processing.
  
  This should be called during application startup.
  Returns the number of events recovered.
  """
  def recover_all_events do
    events = TccDepeeringElixir.BViewEventPersistence.load_events()
    
    if Enum.empty?(events) do
      Logger.info("[BViewRecovery] No pending events to recover")
      0
    else
      Logger.info("[BViewRecovery] Found #{length(events)} pending events")
      
      # Process each event
      Enum.each(events, &recover_event/1)
      
      length(events)
    end
  end

  @doc """
  Recover a single event by its ID.
  """
  def recover_event_by_id(event_id) do
    case TccDepeeringElixir.BViewEventPersistence.get_event(event_id) do
      nil ->
        Logger.warning("[BViewRecovery] Event not found: #{event_id}")
        :error
      
      event ->
        recover_event(event)
        :ok
    end
  end

  # Private functions

  defp recover_event(event) do
    event_id = event["id"]
    state = event["state"]
    
    Logger.info("[BViewRecovery] Recovering event #{event_id} (state: #{state})")
    
    case state do
      "downloading" ->
        resume_from_download(event)
      
      "processing" ->
        resume_from_processing(event)
      
      "parsing" ->
        resume_from_parsing(event)
      
      _ ->
        Logger.warning("[BViewRecovery] Unknown state for event #{event_id}: #{state}")
    end
  end

  defp resume_from_download(event) do
    event_id = event["id"]
    rrc = event["rrc"]
    ripe_month_dir = event["ripe_month_dir"]
    ripe_date = event["ripe_date"]
    time_str = event["time_str"]
    prefix = event["prefix"]
    asn = event["asn"]
    ip_version = event["ip_version"]
    
    Logger.info("[BViewRecovery] Resuming download for #{ripe_date} #{time_str}")
    
    # Resume the full fetch_and_process pipeline
    case TccDepeeringElixir.BViewDownloader.fetch_and_process(
      rrc,
      ripe_month_dir,
      ripe_date,
      time_str,
      prefix,
      asn,
      ip_version
    ) do
      {:ok, %{output_file: output_file, cached: _was_cached}} ->
        Logger.info("[BViewRecovery] Download resumed successfully for #{event_id}")
        # Now proceed to parsing
        resume_from_processing_with_file(event, output_file)
      
      {:error, reason} ->
        Logger.error("[BViewRecovery] Failed to resume download for #{event_id}: #{reason}")
        TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
    end
  end

  defp resume_from_processing(event) do
    event_id = event["id"]
    prefix = event["prefix"]
    rrc = event["rrc"]
    
    # Reconstruct the output file path
    ripe_date = event["ripe_date"]
    time_str = event["time_str"]
    
    output_file = "data/#{rrc}/#{prefix}/output_bview.#{ripe_date}.#{time_str}.txt"
    
    if File.exists?(output_file) do
      Logger.info("[BViewRecovery] Resuming parsing for #{output_file}")
      resume_from_processing_with_file(event, output_file)
    else
      Logger.warning("[BViewRecovery] Output file not found for event #{event_id}: #{output_file}")
      Logger.warning("[BViewRecovery] Cleaning up event: #{event_id}")
      TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
    end
  end

  defp resume_from_processing_with_file(event, output_file) do
    event_id = event["id"]
    rrc = event["rrc"]
    ip_version = event["ip_version"]
    
    Logger.info("[BViewRecovery] Proceeding to parsing for #{event_id}")
    
    case TccDepeeringElixir.BViewCache.parse_or_cache(output_file, rrc, ip_version: ip_version, event_id: event_id, origin_asn: event["origin_asn"]) do
      {:ok, _result, cached: _} ->
        Logger.info("[BViewRecovery] Successfully completed recovery for #{event_id}")
        # Event is automatically completed by parse_or_cache
      
      {:error, reason} ->
        Logger.error("[BViewRecovery] Failed to parse during recovery for #{event_id}: #{reason}")
        TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
    end
  end

  defp resume_from_parsing(event) do
    event_id = event["id"]
    prefix = event["prefix"]
    rrc = event["rrc"]
    ip_version = event["ip_version"]
    
    # Reconstruct the output file path
    ripe_date = event["ripe_date"]
    time_str = event["time_str"]
    
    output_file = "data/#{rrc}/#{prefix}/output_bview.#{ripe_date}.#{time_str}.txt"
    
    if File.exists?(output_file) do
      Logger.info("[BViewRecovery] Resuming parsing from scratch for #{output_file}")
      
      case TccDepeeringElixir.BViewCache.parse_or_cache(output_file, rrc, ip_version: ip_version, event_id: event_id, origin_asn: event["origin_asn"]) do
        {:ok, _result, cached: _} ->
          Logger.info("[BViewRecovery] Successfully completed parsing recovery for #{event_id}")
          # Event is automatically completed by parse_or_cache
        
        {:error, reason} ->
          Logger.error("[BViewRecovery] Failed to parse during recovery for #{event_id}: #{reason}")
          TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
      end
    else
      Logger.warning("[BViewRecovery] Output file not found for parsing event #{event_id}: #{output_file}")
      TccDepeeringElixir.BViewEventPersistence.complete_event(event_id)
    end
  end
end
