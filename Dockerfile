# --- Stage 1: Build ---
FROM hexpm/elixir:1.15.7-erlang-26.2.1-debian-bookworm-20240130-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY assets assets
COPY priv priv
COPY lib lib

RUN mix assets.deploy
RUN mix compile
RUN mix release

# --- Stage 2: Runtime ---
FROM debian:bookworm-slim AS app

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locallang ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
WORKDIR /app

COPY --from=builder /app/_build/prod/rel/tcc_depeering_elixir ./
COPY entrypoint.sh ./

ENV PORT=4000
ENV MIX_ENV=prod
ENV PHX_SERVER=true

EXPOSE 4000

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["bin/tcc_depeering_elixir", "start"]