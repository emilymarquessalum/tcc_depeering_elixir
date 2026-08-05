import Config

if System.get_env("PHX_SERVER") do
  config :tcc_depeering_elixir, TccDepeeringElixirWeb.Endpoint, server: true
end

config :tcc_depeering_elixir, TccDepeeringElixirWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))],
  server: true

if config_env() == :prod do
  # Fallback points to 'db' (the docker-compose service name) instead of 'localhost'
  database_url =
    System.get_env("DATABASE_URL") ||
      "ecto://postgres:postgres@db:5432/tcc_depeering_elixir_prod"

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :tcc_depeering_elixir, TccDepeeringElixir.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :tcc_depeering_elixir, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tcc_depeering_elixir, TccDepeeringElixirWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end