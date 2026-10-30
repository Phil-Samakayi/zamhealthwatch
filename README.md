# ZamHealthWatch

A Public Health Intelligence Platform for Zambia — personal portfolio project, first Elixir/Phoenix build.

**Live demo: [zamhealthwatch.onrender.com](https://zamhealthwatch.onrender.com).** The home page lists demo logins for each role. The free instance sleeps when idle, so the first visit can take about a minute to load.

Started life as a Final Year Project proposal (see `docs/archive/`), then reframed as a broader modular platform once it stopped being an academic deliverable and became something meant to actually solve a problem. The full current spec lives in [`docs/ZamHealthWatch_Project_Brief.md`](docs/ZamHealthWatch_Project_Brief.md) — read that first.

![A case report from a health worker over SMS/USSD flows through Broadway into the Disease Surveillance context, which persists it to Postgres/PostGIS and broadcasts a PubSub event to two independent subscribers: Public Alerts, which enqueues an Oban job to text the community back, and the Epidemiology Dashboard LiveView, which pushes a live update straight to any connected browser — no REST polling layer in either direction.](docs/architecture.svg)

*The mechanism this architecture is actually betting on: one PubSub broadcast reaching both the outbound alert pipeline and the live dashboard, in place of a separate REST API plus client-side polling.*

## Modules

Disease Surveillance · Case Management · Laboratory Reporting · Vaccination Monitoring · Drug Availability · Hospital Capacity · Public Alerts · Health Worker Portal · Epidemiology Dashboard · Predictive Analytics · GIS Mapping · National Reporting

## Stack (planned)

Elixir + Phoenix (LiveView, PubSub) · PostgreSQL + PostGIS via Ecto · Oban (background jobs) · Broadway (SMS/USSD ingestion) · Nx/Axon/Explorer for predictive analytics (Python fallback documented) · Leaflet.js for mapping · Africa's Talking for SMS/USSD.

Full rationale for each choice is in the project brief.

## Development approach

Iterative and evolutionary, following the risk-driven / value-driven planning and GRASP responsibility-assignment ideas from Craig Larman's *Applying UML and Patterns*. [`docs/ITERATIONS.md`](docs/ITERATIONS.md) is the living build log — one entry per iteration, updated as it happens rather than written after the fact: goal, decisions made and why, what got built, current status.

## Dev environment

Native, not containerized. Elixir/Erlang were already installed on the dev machine (1.19.5 / OTP 28), so a Docker dev container turned out to be solving a problem that didn't exist — it's not worth the WSL2/Docker Desktop setup tax on Windows when the actual language toolchain is already there.

Installed and confirmed working:

1. **Elixir 1.19.5 / Erlang OTP 28** — `elixir --version` to check.
2. **PostgreSQL 18 + PostGIS 3.6.2** — via the [EnterpriseDB Windows installer](https://www.postgresql.org/download/windows/) + Stack Builder's PostGIS bundle under "Spatial Extensions." Confirmed with `psql -U postgres -c "SELECT * FROM pg_available_extensions WHERE name LIKE 'postgis%';"`.
3. `mix local.hex && mix local.rebar && mix archive.install hex phx_new` — done; the Phoenix app itself is scaffolded (`mix phx.new . --app zamhealthwatch --module ZamHealthWatch --binary-id`) and boots.

Port 4000 is what Phoenix will use once there's an app to run; Postgres listens on 5432 on `localhost`.

**Shell prompt:** `scripts/activate.ps1` gives you a `(zamhealthwatch)` prompt prefix in PowerShell, the same visual cue Python's venv gives — dot-source it from the project root (`. .\scripts\activate.ps1`), `deactivate` to leave it. Purely cosmetic: Elixir doesn't need dependency isolation the way Python does (Mix already scopes each project's deps to its own `deps/`/`_build/`), so this is just so you can tell at a glance which project's shell you're in.

*(An earlier version of this repo included a Docker dev container under `.devcontainer/`/`docker-compose.yml`. Dropped in favor of the native setup above — if you still have those files locally, safe to delete.)*

## Status

All twelve modules have a working first slice (Iterations 0–13), Iteration 14 deploys the app as a public demo, Iteration 15 adds lab result corrections, and Iteration 16 resets the demo data on boot. See [`docs/ITERATIONS.md`](docs/ITERATIONS.md) for the detail and the deferred follow-ups.

## Deployment

The demo runs on **Render** (free web service, Docker) with **Neon** (free Postgres). PostGIS isn't needed in production: facility coordinates are plain latitude/longitude columns.

- `Dockerfile` builds an Elixir release. On every boot the container runs `ZamHealthWatch.Release.setup/0`, which migrates and seeds, and then starts the server. Both steps are safe to repeat.
- `render.yaml` is a Render Blueprint for the web service. The secrets (`DATABASE_URL`, `SECRET_KEY_BASE`) are entered in the Render dashboard, never committed.
- Nobody can log in by email on the demo because no mail provider is connected. Instead, `ZamHealthWatch.Demo` seeds one password-login account per role, and the home page lists their credentials. Outgoing emails are written to the server log.
- On the free plan the service sleeps after 15 minutes without traffic, so the first visit after that takes about a minute to wake it.
- With `DEMO_RESET_ON_BOOT=true`, every boot also wipes the demo activity (cases, lab tests, stock, capacity, coverage, alert subscribers) and reseeds it dated from that moment. Each visitor after an idle spell gets the same fresh demo, and the risk trend stays current because the free instance restarts whenever it has been idle. Accounts, districts, and facilities are kept. Never set it on a database holding real data.

Required environment variables: `DATABASE_URL` (Neon's direct connection string, not the `-pooler` one), `SECRET_KEY_BASE` (from `mix phx.gen.secret`), and `DATABASE_SSL=true`. The public demo also sets `DEMO_RESET_ON_BOOT=true`. Africa's Talking credentials (`AFRICAS_TALKING_USERNAME`, `AFRICAS_TALKING_API_KEY`) are optional; without them SMS is only logged.

## Docs

- [`docs/ZamHealthWatch_Project_Brief.md`](docs/ZamHealthWatch_Project_Brief.md) — the live spec (vision, scope, architecture).
- [`docs/ITERATIONS.md`](docs/ITERATIONS.md) — the build log, updated per iteration.
- [`docs/archive/FYP_Proposal_Original.md`](docs/archive/FYP_Proposal_Original.md) — the original UNZA Final Year Project proposal this evolved from. Superseded; kept for history only.

## License

All rights reserved. This repository is public so the code, architecture, and build history are visible for portfolio and evaluation purposes — it is not open source. No permission is granted to use, copy, modify, or deploy this software without the copyright holder's prior written consent. See [`LICENSE`](LICENSE).
