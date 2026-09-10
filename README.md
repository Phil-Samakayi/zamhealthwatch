# ZamHealthWatch

A Public Health Intelligence Platform for Zambia — personal portfolio project, first Elixir/Phoenix build.

Started life as a Final Year Project proposal (see `docs/archive/`), then reframed as a broader modular platform once it stopped being an academic deliverable and became something meant to actually solve a problem. The full current spec lives in [`docs/ZamHealthWatch_Project_Brief.md`](docs/ZamHealthWatch_Project_Brief.md) — read that first.

![A case report from a health worker over SMS/USSD flows through Broadway into the Disease Surveillance context, which persists it to Postgres/PostGIS and broadcasts a PubSub event to two independent subscribers: Public Alerts, which enqueues an Oban job to text the community back, and the Epidemiology Dashboard LiveView, which pushes a live update straight to any connected browser — no REST polling layer in either direction.](docs/architecture.svg)

*The mechanism this architecture is actually betting on: one PubSub broadcast reaching both the outbound alert pipeline and the live dashboard, in place of a separate REST API plus client-side polling.*

## Modules

Disease Surveillance · Case Management · Laboratory Reporting · Vaccination Monitoring · Drug Availability · Hospital Capacity · Public Alerts · Health Worker Portal · Epidemiology Dashboard · Predictive Analytics · GIS Mapping · National Reporting

## Stack (planned)

Elixir + Phoenix (LiveView, PubSub) · PostgreSQL + PostGIS via Ecto · Oban (background jobs) · Broadway (SMS/USSD ingestion) · Nx/Axon/Explorer for predictive analytics (Python fallback documented) · Leaflet.js for mapping · Africa's Talking for SMS/USSD.

Full rationale for each choice is in the project brief.

## Development approach

Iterative and evolutionary, following the risk-driven / value-driven planning and GRASP responsibility-assignment ideas from Craig Larman's *Applying UML and Patterns*. No sprint backlog exists yet — the brief deliberately stops at Inception (vision, scope, architecture). Iteration planning is the next step, not yet part of this repo.

## Dev environment

Native, not containerized. Elixir/Erlang were already installed on the dev machine (1.19.5 / OTP 28), so a Docker dev container turned out to be solving a problem that didn't exist — it's not worth the WSL2/Docker Desktop setup tax on Windows when the actual language toolchain is already there.

Installed and confirmed working:

1. **Elixir 1.19.5 / Erlang OTP 28** — `elixir --version` to check.
2. **PostgreSQL 18 + PostGIS 3.6.2** — via the [EnterpriseDB Windows installer](https://www.postgresql.org/download/windows/) + Stack Builder's PostGIS bundle under "Spatial Extensions." Confirmed with `psql -U postgres -c "SELECT * FROM pg_available_extensions WHERE name LIKE 'postgis%';"`.
3. Still to run once, before the first `mix phx.new`: `mix local.hex && mix local.rebar && mix archive.install hex phx_new`.

Port 4000 is what Phoenix will use once there's an app to run; Postgres listens on 5432 on `localhost`.

**Shell prompt:** `scripts/activate.ps1` gives you a `(zamhealthwatch)` prompt prefix in PowerShell, the same visual cue Python's venv gives — dot-source it from the project root (`. .\scripts\activate.ps1`), `deactivate` to leave it. Purely cosmetic: Elixir doesn't need dependency isolation the way Python does (Mix already scopes each project's deps to its own `deps/`/`_build/`), so this is just so you can tell at a glance which project's shell you're in.

No `mix phx.new` scaffold yet — the environment is ready, but starting the actual codebase is deliberately the next step, once iteration planning happens (see Development approach below).

*(An earlier version of this repo included a Docker dev container under `.devcontainer/`/`docker-compose.yml`. Dropped in favor of the native setup above — if you still have those files locally, safe to delete.)*

## Status

Pre-code. This repo currently holds project documentation and the dev environment only.

## Docs

- [`docs/ZamHealthWatch_Project_Brief.md`](docs/ZamHealthWatch_Project_Brief.md) — the live spec.
- [`docs/archive/FYP_Proposal_Original.md`](docs/archive/FYP_Proposal_Original.md) — the original UNZA Final Year Project proposal this evolved from. Superseded; kept for history only.
