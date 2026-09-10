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
- `role` and `facility_id` landed on `User` as a separate migration (`add_role_and_facility_to_users`) rather than folded into the original `phx.gen.auth` migration, since that one was already applied and this is a different, later decision. `role` is `Ecto.Enum` (`:health_worker`, `:district_officer`, `:moh_admin`) stored as a string column; `facility_id` FKs to `facilities` with `on_delete: :nilify_all` so deleting a facility never cascades into deleting a user, just clears the reference. Neither field is wired into registration yet — `mix phx.gen.auth`'s flow only ever collected an email — so both stay nullable at the DB level and `Accounts.assign_user_role/2` is a standalone function, not part of `register_user/1`. A brand-new user has `role: nil` until something (an admin action, an onboarding step — not decided yet) assigns one; that's a real gap, not an oversight, and it's the natural seed for a future iteration once there's a login-gated page that needs to check `current_scope.user.role` for anything.

**Gotchas:**

- `config/test.exs` ships from `mix phx.new` with a placeholder Postgres password (`postgres`) that was never updated to match the actual local install (`config/dev.exs` has the real one). `mix test` failed on `invalid_password` until `config/test.exs` was brought in line with `config/dev.exs`. Worth a second look if `mix ecto.create`/`mix test` ever start failing with auth errors after a fresh clone or a Postgres reinstall.

**Built:**

- [x] Phoenix app scaffold (`mix phx.new . --app zamhealthwatch --module ZamHealthWatch --binary-id`) — native Elixir 1.19.5 / OTP 28, boots against Postgres 18 + PostGIS 3.6.2, confirmed at `localhost:4000`.
- [x] `mix phx.gen.auth Accounts User users`
- [x] Migration: `role` (enum) + `facility_id` (nullable FK) on `users` — plus `Accounts.change_user_role/2` and `Accounts.assign_user_role/2` to actually set them; not called from registration yet (see decisions above).
- [x] `Geography` context: `District`, `Facility` schemas + migrations — stripped of the erroneous per-user scoping described above; migrated cleanly and `mix test` passes (128 tests, 0 failures).

**Status:** done — foundation (District, Facility, User with role/facility) and auth are in, migrated, and tested. Role assignment has no UI or self-registration path yet; that's real remaining work, not part of this slice. Next up: Case Management (Iteration 1).

---

## Iteration 1 — Case Management (domain layer)

**Goal:** the second architecturally-significant, high-risk slice the brief calls out (Disease Surveillance + Case Management, alongside the core domain model, as the two things Elaboration exists to prove out). Smallest useful cut: get a `Case` reported, persisted, and broadcast — not yet through Broadway/SMS, not yet consumed by Public Alerts or the Epidemiology Dashboard. Those are what actually close the report -> persist -> broadcast -> (alert + dashboard) loop that makes this project's MVP; this slice is the "persist" half, built and tested the same way Geography was in Iteration 0 before any UI touches it.

**Decisions:**

- One context, not two. The brief's module table lists **Disease Surveillance** (aggregation by facility/district/disease) and **Case Management** (individual case lifecycle) separately, but they'd both be queries and writes over the same `cases` table right now — no distinct schema or responsibility exists yet to justify splitting them (GRASP High Cohesion/Low Coupling cuts against two contexts fighting over one table). Built as `CaseManagement`, owning `Case` end to end; aggregation queries (`list_cases_by_facility/1` today, by-district/by-disease later) live here too. Revisit and split out `DiseaseSurveillance` if/when aggregation logic grows enough to earn its own boundary — not before.
- `disease` is a plain `Ecto.Enum` on `Case` (`:cholera, :malaria, :typhoid, :covid19, :measles` — the five from the proposal), not a separate reference table. Same call as `role` on `User` in Iteration 0: no per-disease metadata need yet.
- `status` (`:suspected, :confirmed, :resolved`) is also `Ecto.Enum`, defaulting to `:suspected`, but deliberately split into its own `status_changeset/2` separate from the general `changeset/2` — a case can't be created pre-confirmed or pre-resolved by accident. The changeset does *not* enforce that transitions only move forward (`:resolved` back to `:suspected` is allowed at the data layer) — there's no case-management screen yet to make a stricter rule meaningful, so it isn't guessed at. Revisit once one exists.
- Contact tracing links (also named in the brief's Case Management scope) are deferred entirely — no schema, no field. No consumer for them yet, same reasoning as everything else deferred so far in this log.
- `Case.facility_id`/`reported_by_id` are required, `on_delete: :restrict` (not `:nilify_all`, unlike `User.facility_id` in Iteration 0). A case is a historical record; a user's current facility is a profile detail that can safely go blank, but silently losing *which facility a case happened at* or *who reported it* would corrupt the audit trail. Deleting a facility or user with cases attached should fail loudly, not cascade or nilify.
- No role check on `create_case/1` yet (every authenticated user can report a case, `reported_by_id` just has to reference a real user) — same "no authorization use case yet" call as Geography's writes in Iteration 0.
- `CaseLive.Index` (the report + list screen) is one LiveView, not separate report/list/edit routes — same smallest-useful-cut reasoning as the rest of this iteration. It only reports and lists; it deliberately has **no** status-transition controls (confirm/resolve buttons), even though `update_case_status/2` already exists and is tested. There's no role-gated workflow yet to decide who's allowed to move a case through its lifecycle, so a button that just calls it would be guessing at that workflow. Revisit once one exists.
- `reported_by_id` is never a field on the report form and is never cast from client params in the LiveView — `CaseLive.Index` sets it from `current_scope.user.id` itself, after the params come in, the same way `user_id`-style fields are handled per the project's Ecto conventions. (`Case.changeset/2` itself still casts `reported_by_id` from `attrs`, unchanged from how Iteration 1 first wrote it — the LiveView is what closes the gap by only ever passing it a trustworthy value.)
- The case list shows every case, not just the current user's or their facility's — same "no authorization use case yet" reasoning as everywhere else. It also doesn't show *who* reported each case; `Accounts` has no `list_users`/lookup-by-id-for-display function yet and this slice didn't need one, so reporter identity stays out of the UI until something needs it.
- `CaseManagement.list_cases/0` gained an explicit `order_by: [desc: :inserted_at]` (previously unordered) so the live list reads newest-first. Small, backward-compatible change to the existing context function rather than a second query — nothing was relying on `list_cases/0`'s prior (unspecified) order.

**Built:**

- [x] Migration: `cases` table (`disease`, `status`, `facility_id`, `reported_by_id`, indexed on all four).
- [x] `CaseManagement` context + `Case` schema — `list_cases/0`, `list_cases_by_facility/1`, `get_case!/1`, `create_case/1`, `update_case_status/2`, `change_case/2`, `change_case_status/2`, PubSub broadcast (`"cases"` topic) on create/update.
- [x] Fixtures + tests mirroring the Geography/Accounts pattern.
- [x] `CaseLive.Index` at `/cases` (authenticated, grouped into the existing `live_session :require_authenticated_user` — see the router comment) — a report form (disease + facility, `reported_by_id` always the current user) above a live-updating list of all reported cases, subscribed to the `"cases"` PubSub topic so every connected viewer sees new/updated cases without a refresh. Tests cover: auth redirect, empty state, listing existing cases, reporting a valid case, validation errors, the server overriding a tampered `reported_by_id`, and the live broadcast reaching a second connected viewer.
- [ ] Public Alerts subscriber (Oban job on case-report broadcast; mock/log delivery before real Africa's Talking sandbox wiring).
- [ ] Epidemiology Dashboard subscriber (LiveView showing cases live as they're reported).

**Gotchas:**

- This slice's code (`CaseLive.Index`, the `router.ex` route, the `list_cases/0` ordering change, and their tests) was written and cross-checked by hand against the existing patterns and this project's `AGENTS.md` — the cloud sandbox it was written in has no route to `hex.pm`/`builds.hex.pm` (so `mix deps.get` can't even install Hex) and can't drive a terminal on the linked Windows machine (terminal/IDE apps are click-only, no typing, under that session's remote-control permission tier), so `mix test` had to be run locally instead of in-session. First run: 16/18 passed, 2 failures, both in the test file rather than `CaseLive.Index` itself — `"can't be blank"` was asserted with a literal apostrophe against HTML that (correctly) renders it escaped as `can&#39;t be blank`, and the tampered-`reported_by_id` test tried to drive a fake form field through `form/3`, which validates params against real DOM fields and rightly refused one that doesn't exist (fixed by pushing the event directly with `render_submit(lv, "save", params)` instead, which is the correct way to simulate a forged payload). Second run, after those two fixes: all 18 green.
- Worth remembering for future iterations: any Ecto default error message containing a `'` (e.g. "can't be blank") needs to be asserted HTML-escaped (`can&#39;t be blank`) in a LiveView test's rendered output.

**Status:** done and `mix test`-verified (18/18, including the `CaseManagement` context suite). Case reporting and the live case list close the report → persist → broadcast loop end-to-end. Public Alerts and the Epidemiology Dashboard are the next slice.
