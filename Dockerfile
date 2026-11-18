# syntax=docker/dockerfile:1
# Laboratório de TESTE (docs/flows/22-docker-lab.md): UMA imagem para todos os papéis (BRDC_ROLE=validator|wallet|
# equivocator). Inclui `brdc_dev` e roda com chaves de teste: NÃO é produção.
#
# A base de build e a de runtime têm de ser da MESMA distribuição (glibc e OpenSSL iguais), porque a release leva o
# Erlang junto: a imagem oficial do Elixir 1.20.4/OTP 29 é Debian 13 (trixie), então o runtime é debian:trixie-slim.
ARG ELIXIR_TAG=1.20.4-otp-29-slim
ARG RUNTIME_TAG=trixie-slim

# ---------------------------------------------------------------- build
FROM elixir:${ELIXIR_TAG} AS build
ENV MIX_ENV=prod LANG=C.UTF-8
# git: duas dependências da web (heroicons, daisyui) vêm do GitHub
RUN apt-get update \
 && apt-get install -y --no-install-recommends git build-essential ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN mix local.hex --force && mix local.rebar --force

# dependências primeiro, para o cache da build só se perder quando mix.lock ou algum mix.exs mudar
COPY mix.exs mix.lock ./
COPY config config
COPY apps/brdc_crypto/mix.exs apps/brdc_crypto/mix.exs
COPY apps/brdc_ledger/mix.exs apps/brdc_ledger/mix.exs
COPY apps/brdc_consensus/mix.exs apps/brdc_consensus/mix.exs
COPY apps/brdc_p2p/mix.exs apps/brdc_p2p/mix.exs
COPY apps/brdc_node/mix.exs apps/brdc_node/mix.exs
COPY apps/brdc_web/mix.exs apps/brdc_web/mix.exs
COPY apps/brdc_dev/mix.exs apps/brdc_dev/mix.exs
RUN mix deps.get --only prod && mix deps.compile

COPY apps apps
RUN mix compile
# tailwind e esbuild baixam os próprios binários (precisa de rede na build)
RUN cd apps/brdc_web && mix assets.setup && mix assets.deploy
RUN mix release brdc

# ---------------------------------------------------------------- runtime
FROM debian:${RUNTIME_TAG} AS runtime
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 libncurses6 libsctp1 openssl ca-certificates bash \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 1000 --home-dir /app --shell /usr/sbin/nologin brdc \
 && mkdir -p /data \
 && chown brdc:brdc /data
WORKDIR /app
COPY --from=build --chown=brdc:brdc /src/_build/prod/rel/brdc ./
USER brdc
ENV LANG=C.UTF-8
# os volumes novos herdam o dono de /data (brdc), então o validador grava os blocos sem ser root
VOLUME ["/data"]
ENTRYPOINT ["/app/bin/brdc"]
CMD ["start"]
