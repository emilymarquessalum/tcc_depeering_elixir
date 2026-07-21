defmodule TccDepeeringElixir.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TccDepeeringElixirWeb.Telemetry,
      TccDepeeringElixir.Repo,
      {DNSCluster, query: Application.get_env(:tcc_depeering_elixir, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TccDepeeringElixir.PubSub},
      TccDepeeringElixir.BViewRequestLimiter,
      # Start a worker by calling: TccDepeeringElixir.Worker.start_link(arg)
      # {TccDepeeringElixir.Worker, arg},
      # Start to serve requests, typically the last entry
      TccDepeeringElixirWeb.Endpoint
    ]
 
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TccDepeeringElixir.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Recover any incomplete events after startup
        spawn(fn ->
          Process.sleep(1000)  # Give the system a moment to stabilize
          TccDepeeringElixir.BViewRecovery.recover_all_events()
        end)
        {:ok, pid}
      
      other ->
        other
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TccDepeeringElixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
