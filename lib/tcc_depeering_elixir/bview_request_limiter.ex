defmodule TccDepeeringElixir.BViewRequestLimiter do
  @moduledoc """
  GenServer that limits concurrent bview requests to a configurable maximum.
  Requests will wait if the limit is reached until a slot becomes available.
  """
  use GenServer

  # Configure this to change max concurrent requests
  @max_concurrent_requests 1

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Acquire a request slot. Blocks until a slot is available, then returns {:ok, request_id}.
  """
  def acquire() do
    
    GenServer.call(__MODULE__, :acquire, :infinity)
  end

  @doc """
  Releases a request slot and processes any waiting requests.
  """
  def release(request_id) do
    GenServer.cast(__MODULE__, {:release, request_id})
  end

  @doc """
  Gets current active request count.
  """
  def active_count() do
    GenServer.call(__MODULE__, :count)
  end

  @impl true
  def init(_opts) do
    {:ok, %{active_requests: 0, next_request_id: 0, waiting_queue: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, from, state) do
    if state.active_requests < @max_concurrent_requests do
      new_state = %{
        state
        | active_requests: state.active_requests + 1,
          next_request_id: state.next_request_id + 1
      }

      {:reply, {:ok, state.next_request_id}, new_state}
    else
      # Queue the request and don't reply yet
      new_queue = :queue.in(from, state.waiting_queue)
      {:noreply, %{state | waiting_queue: new_queue}}
    end
  end

  def handle_call(:count, _from, state) do
    {:reply, state.active_requests, state}
  end

  @impl true
  def handle_cast({:release, _request_id}, state) do
    new_active = max(0, state.active_requests - 1)
    new_queue = state.waiting_queue

    # Process waiting requests if slots are available
    {new_active_count, updated_queue, final_next_id} =
      process_waiting_requests(new_active, new_queue, state.next_request_id + 1)

    new_state = %{
      state
      | active_requests: new_active_count,
        waiting_queue: updated_queue,
        next_request_id: final_next_id - 1
    }

    {:noreply, new_state}
  end

  defp process_waiting_requests(active_count, queue, next_id) do
    if active_count < @max_concurrent_requests && not :queue.is_empty(queue) do
      {{:value, from}, new_queue} = :queue.out(queue)
      GenServer.reply(from, {:ok, next_id})
      process_waiting_requests(active_count + 1, new_queue, next_id + 1)
    else
      {active_count, queue, next_id}
    end
  end
end
