


defmodule TccDepeeringElixirWeb.LookingGlassController do
  use TccDepeeringElixirWeb, :controller

  def read_prefixes(conn, params) do
    url = Map.get(params, "url", "https://lg.ix.br/routeservers/SP-rs1-v4?s=routes_accepted&o=desc")
  end
end