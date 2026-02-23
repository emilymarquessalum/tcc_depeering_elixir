defmodule TccDepeeringElixir.Repo do
  use Ecto.Repo,
    otp_app: :tcc_depeering_elixir,
    adapter: Ecto.Adapters.Postgres
end
