# Iteration Log

One entry per iteration: the goal, decisions made (and why), what actually got built, and current status. The project brief (`ZamHealthWatch_Project_Brief.md`) is the static vision/Inception doc and shouldn't need to change often; this file is where the plan meets reality, updated as each iteration progresses rather than written once after the fact.

---

## Iteration 0 — Core domain model + auth

**Goal:** risk-reducing spike. The shared foundation every other module depends on (District, Facility, User + role), plus first real hands-on Elixir/Phoenix — deliberately the smallest slice, not Case/Case Management yet (that's Iteration 1).

**Decisions:**

- Role modeled as an enum field on `User` (`:health_worker`, `:district_officer`, `:moh_admin`), not a separate `Role` schema — no use case yet for role-specific attributes or a user holding multiple roles. Revisit only if a real need for that shows up.
- `facility_id` on `User` is nullable — health workers belong to a facility, but district/national-level users shouldn't be forced into one that doesn't fit.
- `Facility` gets no geospatial column yet, even though GIS Mapping is coming later — adding it now would be designing ahead of the iteration that needs it. Trivial migration when that iteration arrives.
- Two contexts: `Accounts` (User, auth) and `Geography` (District, Facility) — kept decoupled; `Accounts` stores `facility_id` as a plain reference and calls `Geography`'s public API for details rather than reaching into its schemas directly.
- Auth via `mix phx.gen.auth`, not hand-rolled — idiomatic, already tested, no reason to reinvent it.
- `District`/`Facility` are shared reference data, not per-user resources. `mix phx.gen.context` auto-detected the `Scope` module `phx.gen.auth` installs and defaulted both to user-owned (a `user_id` FK with `on_delete: :delete_all`, ownership checks on every read/write, per-user PubSub topics) — the same "belongs to whoever created it" assumption that's right for something like account settings and wrong here, since every role needs to see and (eventually, role-gated) edit the same districts and facilities. Stripped `user_id`/`Scope` out of the migrations, schemas, and context entirely before migrating; `Geography`'s public functions now take no scope argument, and PubSub broadcasts go out on plain `"districts"`/`"facilities"` topics. Revisit only when a real write-authorization need shows up (e.g. "only `moh_admin` edits districts") — that's a role check inside the existing functions, not a schema change.

**Gotchas:**

- `config/test.exs` ships from `mix phx.new` with a placeholder Postgres password (`postgres`) that was never updated to match the actual local install (`config/dev.exs` has the real one). `mix test` failed on `invalid_password` until `config/test.exs` was brought in line with `config/dev.exs`. Worth a second look if `mix ecto.create`/`mix test` ever start failing with auth errors after a fresh clone or a Postgres reinstall.

**Built:**

- [x] Phoenix app scaffold (`mix phx.new . --app zamhealthwatch --module ZamHealthWatch --binary-id`) — native Elixir 1.19.5 / OTP 28, boots against Postgres 18 + PostGIS 3.6.2, confirmed at `localhost:4000`.
- [x] `mix phx.gen.auth Accounts User users`
- [ ] Migration: `role` (enum) + `facility_id` (nullable FK) on `users`
- [x] `Geography` context: `District`, `Facility` schemas + migrations — stripped of the erroneous per-user scoping described above; migrated cleanly and `mix test` passes (128 tests, 0 failures).

**Status:** in progress — auth and Geography are in and tested; still need the `role`/`facility_id` migration on `users` before Iteration 0 is done.
