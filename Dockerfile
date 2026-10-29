# Builds ZamHealthWatch as an Elixir release and runs it (Iteration 14 -
# deployment to Render, database on Neon; see docs/ITERATIONS.md).
#
# Adapted from what `mix phx.gen.release --docker` generates for Phoenix
# 1.8, with two deliberate differences:
#
#   * Both stages use the official `elixir` slim image rather than a
#     dated hexpm/elixir builder plus a separate plain Debian runner. The
#     runner then carries Elixir it doesn't strictly need, but it's
#     guaranteed to share the builder's OpenSSL and libc versions - a
#     mismatch there makes a release fail at boot with an error that
#     says nothing about the actual cause.
#   * No rel/overlays scripts. Migrating, seeding, and starting the
#     server are one shell command at the bottom, so there are no
#     executable-bit problems from files committed on Windows.
#
# Elixir 1.19.6 here vs 1.19.5 in local development is a patch-level
# difference: this is the current 1.19 image on Docker Hub.

ARG ELIXIR_IMAGE=elixir:1.19.6-otp-28-slim

FROM ${ELIXIR_IMAGE} AS builder

# git: heroicons and daisyUI are git dependencies in mix.exs.
# build-essential: for any dependency that compiles a native extension.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Dependencies first, so editing app code doesn't invalidate this layer.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv
COPY lib lib

# Compile before building assets: Phoenix 1.8 extracts colocated
# hooks/JS during compilation, and esbuild needs them to exist.
RUN mix compile

COPY assets assets
RUN mix assets.deploy

# runtime.exs last - changing it shouldn't recompile anything.
COPY config/runtime.exs config/
RUN mix release


FROM ${ELIXIR_IMAGE} AS runner

# ca-certificates: the Neon connection verifies the server's TLS
# certificate against the OS trust store (see config/runtime.exs), and
# Africa's Talking's API is HTTPS too.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod" \
    LANG="C.UTF-8" \
    LC_ALL="C.UTF-8"

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/zamhealthwatch ./

USER nobody

# Migrate and seed (ZamHealthWatch.Release.setup/0 - both safe on every
# boot), then start the server. PHX_SERVER is set only for the final
# `start`, so the seeding step boots the app without opening the HTTP
# port. `exec` makes the release PID 1, so Render's stop signal reaches
# the BEAM directly.
CMD ["sh", "-c", "/app/bin/zamhealthwatch eval 'ZamHealthWatch.Release.setup()' && PHX_SERVER=true exec /app/bin/zamhealthwatch start"]
