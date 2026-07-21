defmodule TccDepeeringElixir.BViewEventPersistence do
  @moduledoc """
  Manages persistence of ongoing bgpdump processing events.
  
  Saves event state to disk to survive system restarts.
  Only keeps ongoing events - completed ones are removed.
  
  Event states:
    - :downloading - Downloading .gz file
    - :processing - Running bgpdump to create .txt file
    - :parsing - Parsing .txt file and creating cache
  """

  require Logger

  @events_file "data/.bview_events"

  @doc """
  Get the path to the events persistence file.
  """
  def events_file_path do
    @events_file
  end

  @doc """
  Start tracking a new event.
  
  Returns the unique event ID.
  """
  def start_event(rrc, ripe_month_dir, ripe_date, time_str, prefix, asn, origin_asn, ip_version) do
    event_id = generate_event_id(rrc, ripe_date, time_str, prefix, asn)
    
    event = %{
      "id" => event_id,
      "rrc" => rrc,
      "ripe_month_dir" => ripe_month_dir,
      "ripe_date" => ripe_date,
      "time_str" => time_str,
      "prefix" => prefix,
      "asn" => asn,
      "origin_asn" => origin_asn,
      "ip_version" => ip_version,
      "state" => "downloading",
      "started_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "last_updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    add_event(event)
    event_id
  end

  @doc """
  Update event state to the next stage.
  """
  def update_event_state(event_id, new_state) when new_state in ["downloading", "processing", "parsing"] do
    events = load_events()
    
    updated_events = 
      Enum.map(events, fn event ->
        if event["id"] == event_id do
          %{event | 
            "state" => new_state,
            "last_updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        else
          event
        end
      end)
    
    persist_events(updated_events)
  end

  @doc """
  Mark an event as completed and remove it from persistence.
  """
  def complete_event(event_id) do
    events = load_events()
    
    remaining_events = 
      Enum.reject(events, fn event ->
        event["id"] == event_id
      end)
    
    persist_events(remaining_events)
    Logger.info("Completed event: #{event_id}")
  end

  @doc """
  Load all ongoing events from disk.
  """
  def load_events do 
    []
  end

 

  @doc """
  Get a specific event by ID.
  """
  def get_event(event_id) do
    load_events()
    |> Enum.find(&(&1["id"] == event_id))
  end

  @doc """
  List all ongoing events.
  """
  def list_events do
    load_events()
  end

  @doc """
  Clear all events (only use for testing or manual recovery).
  """
  def clear_all_events do
    File.rm(@events_file)
    :ok
  rescue
    _e -> :ok
  end

  # Private functions

  defp add_event(event) do
    events = load_events()
    updated_events = [event | events]
    persist_events(updated_events)
  end

  defp persist_events(events) do
    content = Jason.encode!(events)
    case File.write(@events_file, content) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to persist events: #{inspect(reason)}")
    end
  end

  defp generate_event_id(rrc, ripe_date, time_str, prefix, asn) do
    "#{rrc}_#{ripe_date}_#{time_str}_#{prefix}_#{asn}"
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0..15)
  end
end
