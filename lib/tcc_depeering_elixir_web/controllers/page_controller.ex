defmodule TccDepeeringElixirWeb.PageController do
  use TccDepeeringElixirWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
