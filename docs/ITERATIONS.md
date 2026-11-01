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
- [x] Public Alerts subscriber — `PublicAlerts.Subscriber` (a permanent `GenServer`, subscribed to `"cases"` since app boot) turns every `{:created, case}` broadcast into an `AlertWorker` (`Oban`) job; `AlertWorker` re-fetches the case by id and logs a mock alert (`Logger.info`, stand-in for the real Africa's Talking SMS/USSD call). See the decisions and gotchas below for why Oban now and two real testing wrinkles this raised.
- [x] Epidemiology Dashboard — `EpidemiologyLive.Index` at `/epidemiology`, live via the same `"cases"` PubSub topic. See the decisions sub-section below for scope.

**Decisions (Public Alerts sub-slice):**

- Oban, not a bare `Task.start/1` or inline send, even though delivery is only a log line right now. The brief's real target is SMS/USSD delivery over the network, which fails and needs retrying; proving out *that* shape now (persisted, retryable, queued job triggered by a PubSub event) is the actual risk this sub-slice exists to close, per Iteration 1's goal. Swapping `AlertWorker.perform/1`'s body for a real `Req` call later shouldn't touch the subscriber, the queue config, or anything else.
- `PublicAlerts.Subscriber` only reacts to `{:created, case}}`, not `{:updated, case}}` — alerting on every status change (e.g. `:suspected` → `:resolved`) isn't part of this sub-slice; only the initial report fires an alert. Revisit if a real use case for change-alerts shows up.
- `AlertWorker`'s job args carry just `case_id`, not a serialized `Case` — the standard Oban pattern (args round-trip through JSON in the `oban_jobs` table regardless, and a job that runs later should see the case's current row, not a stale snapshot from when it was enqueued).
- `start_public_alerts_subscriber` is a config flag (`true` in dev/prod, `false` in test) gating whether `Application.start/2` starts `PublicAlerts.Subscriber` at all, rather than always starting it and special-casing test behavior inside the `GenServer`. See the gotcha below for why test needed this.

**Decisions (Epidemiology Dashboard sub-slice):**

- Scope: total case count, counts by disease, counts by status, and counts by facility. Counts **by district** are explicitly deferred, not just left out — `Geography.Facility.changeset/2` casts only `:name`; `district_id` exists as a column on the schema but has no changeset field and no UI anywhere to set it, so every facility's `district_id` is `nil` today. A "by district" aggregate over data that's currently all-`nil` would render either as a single meaningless "unknown district" bucket or silently wrong groupings — worse than not having it. By-facility is what's actually usable today: real, distinct, non-null facility identities. Revisit once `Facility` gets district assignment (its own small slice: cast `district_id`, add it to some facility-management UI) — the aggregate query itself (`group_by: c.facility_id` → `group_by: f.district_id` via a join, or composed in memory like by-facility already is) is a small, mechanical follow-up once that data exists, not a redesign.
- Same "context stays name-agnostic, caller composes" split as `CaseLive.Index`/`Geography.list_facilities/0`: `count_cases_by_facility/0` returns `%{facility_id => count}`, and `EpidemiologyLive.Index` joins in facility names in memory. Keeps `CaseManagement` and `Geography` decoupled, consistent with every other cross-context read so far in this project.
- `count_cases_by_disease/0`/`count_cases_by_status/0` return maps that simply omit a value with zero cases (an `Ecto.Enum` `group_by` only ever produces rows for values that exist) rather than zero-filling. Zero-filling for display — so the dashboard always shows all five disease tiles and all three status tiles, even at 0 — is done in the LiveView from its own hardcoded option lists, the same "each LiveView owns its own display list" precedent `CaseLive.Index` already set with `@disease_options`. This does mean `@disease_options` is now duplicated between the two LiveViews; not extracted to a shared spot yet since there's only two consumers - revisit (rule of three) if a third one shows up.
- The dashboard recomputes all four aggregates from scratch on every `{:created, _}`/`{:updated, _}` broadcast rather than tracking incremental deltas per stat. Simpler and much less error-prone, and cheap enough at this iteration's case volume (a district-level surveillance tool, not a national firehose) — not a real performance concern yet. Revisit only if case volume or broadcast frequency ever makes this measurably slow.
- `/epidemiology` sits behind login, in the same `live_session :require_authenticated_user` as `/cases` — there's no separate public-facing route or auth model yet (that's what the Public Alerts SMS/USSD pipeline is for), so it defaults to the same access as everything else that needs a login today.

**Gotchas:**

- This slice's code (`CaseLive.Index`, the `router.ex` route, the `list_cases/0` ordering change, and their tests) was written and cross-checked by hand against the existing patterns and this project's `AGENTS.md` — the cloud sandbox it was written in has no route to `hex.pm`/`builds.hex.pm` (so `mix deps.get` can't even install Hex) and can't drive a terminal on the linked Windows machine (terminal/IDE apps are click-only, no typing, under that session's remote-control permission tier), so `mix test` had to be run locally instead of in-session. First run: 16/18 passed, 2 failures, both in the test file rather than `CaseLive.Index` itself — `"can't be blank"` was asserted with a literal apostrophe against HTML that (correctly) renders it escaped as `can&#39;t be blank`, and the tampered-`reported_by_id` test tried to drive a fake form field through `form/3`, which validates params against real DOM fields and rightly refused one that doesn't exist (fixed by pushing the event directly with `render_submit(lv, "save", params)` instead, which is the correct way to simulate a forged payload). Second run, after those two fixes: all 18 green.
- Worth remembering for future iterations: any Ecto default error message containing a `'` (e.g. "can't be blank") needs to be asserted HTML-escaped (`can&#39;t be blank`) in a LiveView test's rendered output.
- Making `PublicAlerts.Subscriber` a permanent, globally-named `GenServer` (the natural design — it needs to live for the app's whole lifetime) collided hard with the Ecto SQL Sandbox: left running during `mix test`, it would react to *every* test's `case_fixture()` calls (from whichever process, on whichever sandboxed connection that test owns) and try to write an `Oban` job through a `Repo` connection it was never granted access to — `DBConnection.OwnershipError` crashes, non-deterministically, potentially across the *entire* async suite rather than just this feature's own tests. Fixed by not starting it automatically in `:test` at all (the `start_public_alerts_subscriber` config flag) and having its own tests start a private instance per test with `start_supervised!/1` + `Ecto.Adapters.SQL.Sandbox.allow/3` to grant that one instance access to that one test's connection. Worth remembering for *any* future long-lived process that touches `Repo` from outside the test's own process.
- `mix.exs` gained a new dependency (`{:oban, "~> 2.18"}`, resolved to `2.24.1`) and there's a new migration (`add_oban_jobs_table.exs`, Oban's own standard install migration) — needs `mix deps.get` and `mix ecto.migrate` before `mix test` will pass, not just a fresh `mix test` like the last few slices. `mix deps.get` itself hit a `hex.pm` fetch timeout the first couple of tries (network-side, unrelated to this project) — resolved once by setting `$env:HEX_HTTP_TIMEOUT=300` in PowerShell before retrying (note: PowerShell doesn't take `VAR=val cmd` inline like bash/sh — has to be `$env:VAR=val` on its own line first).
- The real wrinkle: `AlertWorkerTest` asserting on `capture_log`'s output kept coming back empty, three attempts in before landing on the actual fix. `config/test.exs` sets the global Logger level to `:warning` to keep test output quiet, which silently drops the worker's `Logger.info` call before `capture_log` ever sees it. `capture_log([level: :info], fn -> ... end)` didn't help — that only relaxes `capture_log`'s own capturing handler, not the primary level filter that already dropped the event upstream. `Logger.put_process_level(self(), :info)` didn't help either, for reasons not fully pinned down (most likely `Oban.Testing.perform_job/3` not running the worker in the exact test process the override was scoped to). What actually worked: reconfiguring the level directly with `Logger.configure(level: :info)` around the `capture_log` call, restored via `on_exit`, with that one test file marked `async: false` to close off the narrow window where the global change could affect another concurrently-running test. Worth remembering for any future test that needs to assert on log output below the configured test level.

**Status:** done and `mix test`-verified — all three boxes built and green: case reporting/live list, the mock Public Alerts pipeline (report → persist → broadcast → alert), and the Epidemiology Dashboard (report → persist → broadcast → live aggregate counts). Epidemiology Dashboard slice verified on its own (21 tests, 0 failures covering `case_management_test.exs` + the new `epidemiology_live/index_test.exs`); Public Alerts + case reporting were verified earlier (156 tests, 0 failures). Iteration 1 is closed — no known gaps left except the logged, deliberate ones above (by-district aggregation, role-gated status transitions, reporter identity in the case list). Next: pick the first Iteration 2 slice.

---

## Iteration 2 — Inbound SMS/USSD reporting (Broadway)

**Goal:** the brief's other headline feature (alongside the dashboard/alerts already built) and the last architecturally-novel risk Elaboration hadn't yet retired — a demand-driven, backpressure-handling ingestion pipeline, structurally unlike the LiveView/PubSub/Oban patterns already proven in Iterations 0–1. Smallest useful cut: a webhook shaped like Africa's Talking's inbound SMS callback, feeding a Broadway pipeline that parses a small fixed report grammar and calls the same `CaseManagement.create_case/1` the web form already uses — proving the pipeline architecture, not building USSD's session/menu flow or wiring a live Africa's Talking sandbox account, both deferred and logged below.

**Decisions:**

- Custom `GenStage` producer (`SmsReporting.Producer`), not one of Broadway's off-the-shelf producers (SQS/RabbitMQ/Kafka) — none of those fit "a webhook controller pushes messages in as HTTP requests arrive." A hand-rolled producer (a `:queue` + outstanding-demand counter, fed by `handle_cast/2`) is the standard, documented Broadway pattern for a push-based source, and small enough to review by hand rather than trust to an unverified third-party Hex package (this session's sandbox can't reach `hex.pm` to check one exists/still matches its docs before committing the project to depending on it).
- `SmsWebhookController`'s only job is pushing the raw message into the pipeline and responding `200` — always `200`, even on a malformed payload or a report that later fails to parse. A webhook provider expects a fast ack regardless of downstream outcome; returning anything else risks it retrying, which is exactly what `id`/`linkId`-based dedup would guard against once real delivery exists (not built yet — see gap below).
- Fixed grammar `REPORT <DISEASE> <FACILITY_CODE>` (case-insensitive), not free text. Free-text parsing is a real NLP problem this iteration isn't taking on; USSD's guided, stateful menu flow is a structurally different, session-based integration, not a variant of this one. Both are logged gaps, not silently folded in.
- `Facility` gained a required `code` field (short, uppercase, unique — e.g. `"UTH"`) so an SMS can address a facility at all; a `name` (spaces, arbitrary length) or a `binary_id` (nobody types a UUID on a feature phone) don't work for that. Required on every facility now, not just SMS-reported ones — one consistent identity scheme, not "has a code" as a special case. No backfill migration was written for the four already-seeded facilities; `mix ecto.reset` was the pragmatic call for four rows of dev seed data (same call this project already made in Iteration 0 for stripping erroneous `Scope`/`user_id` scaffolding rather than half-supporting it).
- `User` gained a nullable `phone` field and `Accounts.find_or_create_sms_reporter/1`, rather than making `Case.reported_by_id` nullable for SMS reports. Iteration 1 deliberately made `reported_by_id` required + `on_delete: :restrict` specifically to protect the audit trail (a case is a historical record; silently losing who reported it would corrupt it) — an SMS report should still point at a real, identifiable `User` row, just one identified by phone instead of email/password. A user created this way lands with `role: nil` and no `facility_id`, the exact "seed for a future role-assignment iteration" state Iteration 0's decision log already anticipated — no new concept needed, just a second producer of that state.
- `Pipeline.push/2` reaches the running producer via `Broadway.producer_names/1` + `GenStage.cast/2` — the documented mechanism for feeding a custom Broadway producer from outside the pipeline, since Broadway supervises producer processes internally rather than exposing a name `Producer` itself registers.
- One processor stage, no batcher. Report volume at this iteration doesn't call for batching DB writes, and proving Broadway's demand-driven wiring is the point of this slice, not batching. Revisit if real volume ever makes batched inserts worth it.
- No error feedback to the SMS sender on a rejected report (bad grammar, unknown disease, unknown facility) — `Pipeline` logs a warning and marks the message failed; that's it. A reply requires real outbound SMS delivery, which `PublicAlerts.AlertWorker` still only mocks (`Logger.info`). Revisit together, once real Africa's Talking delivery exists for either direction.
- No live Africa's Talking sandbox account is wired up this iteration — the webhook is shaped to match their inbound-SMS payload (`from`, `to`, `text`, `id`, `date`, `linkId`) but only `from`/`text` are used, and nothing yet calls their outbound API. Registering a sandbox account, tunneling a public URL to it, and using `id`/`linkId` for delivery-retry dedup are all real, deliberately deferred follow-ups.

**Built:**

- [x] Migrations: `facilities.code` (unique), `users.phone` (unique, nullable).
- [x] `Facility.changeset/2` requires `code`; `Geography.get_facility_by_code/1`.
- [x] `User.sms_reporter_changeset/2`; `Accounts.find_or_create_sms_reporter/1`.
- [x] `SmsReporting` context — `report_from_sms/2` (parse → resolve facility → resolve/create reporter → `CaseManagement.create_case/1`).
- [x] `SmsReporting.Producer` (custom `GenStage` push producer) + `SmsReporting.Pipeline` (the `Broadway` module), started in the supervision tree behind a `:start_sms_reporting_pipeline` config flag (off in test — same Ecto Sandbox risk as `PublicAlerts.Subscriber`, see gotcha below).
- [x] `SmsWebhookController` at `POST /webhooks/sms`, outside the `:browser` pipeline (no CSRF token from a webhook provider).
- [x] Seed data (`priv/repo/seeds.exs`) updated with real facility codes (UTH/KBW/NTH/MMH).

**Gotchas:**

- Same Ecto Sandbox problem as `PublicAlerts.Subscriber` in Iteration 1, one level harder to fix: `SmsReporting.Pipeline`'s Broadway processor processes aren't a single well-known pid the way a plain `GenServer` is, so there's no one pid to hand to `Sandbox.allow/3`. Fix: `Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})` for the duration of any test that starts a real pipeline instance (restored via `on_exit`), letting any process use that test's checked-out connection — Ecto's own documented answer for "a background process, not started by the test process itself, needs DB access." Known trade-off: shared mode is process-wide, not perfectly isolated from other concurrently-running async tests during that window — same category of imperfection as Iteration 1's temporary global Logger-level change. Every test file that does this is marked `async: false`.
- Two different test modules both need a running `SmsReporting.Pipeline`: `sms_reporting_test.exs` starts uniquely-named instances per test (`:"sms_pipeline_test_#{System.unique_integer()}"`) to prove the Producer → Pipeline → DB path in isolation; `sms_webhook_controller_test.exs` is the one place that starts the pipeline under its real default name (matching what `Pipeline.push/1` and `ZamHealthWatch.Application` both use), since the controller always pushes to the default name. Kept those in separate test files specifically so nothing races to register that default name twice.
- `mix.exs` gains `{:broadway, "~> 1.0"}` — needs `mix deps.get` before `mix test` will even compile. This is the first dependency this session added without being able to verify its exact current API against real docs (no `hex.pm`/hexdocs route from this sandbox) — if `mix test` fails on something Broadway-specific (`Broadway.producer_names/1`, the producer's `child_spec`/`start_link` wiring, `Broadway.Message.failed/2`), that's the most likely place, not the surrounding application logic. Flagged up front rather than discovered as a surprise.

- First real test run (183 tests, 8 failures) confirmed the flagged Broadway-API risk above was justified, and surfaced one more gap this design missed entirely:
  - `Producer` emitting raw maps crashed with `the produced message is invalid. All messages must be a %Broadway.Message{} struct` — wrong assumption that Broadway auto-wraps a custom producer's raw events. Fixed with a `:transformer` option on the producer spec (`SmsReporting.Pipeline.transform/2`) plus a small hand-written `SmsReporting.Acknowledger` (`@behaviour Broadway.Acknowledger`, no-op `ack/3`) — written by hand rather than reaching for a built-in Broadway no-op acknowledger module, since this session still can't check Broadway's exact current module names against live docs.
  - Every `find_or_create_sms_reporter/1` insert failed on `null value in column "email"` — `phx.gen.auth`'s original migration made `users.email` `null: false`, an assumption that held until this iteration added a second way to become a user. Fixed with a new migration (`make_users_email_nullable.exs`) rather than touching the original, already-applied one. The existing unique index on `email` is unaffected — Postgres allows multiple `NULL`s under a unique index by default, so several email-less SMS reporters don't collide.

- One more thing the first green run exposed (not a failure, a test-quality gap): the webhook controller's "well-formed inbound SMS" test posted `REPORT CHOLERA UTH` without ever creating a facility with that code, so it only proved the controller still returns `200` — the same thing the malformed-payload test already covered — not that the happy path actually creates a case. `Logger.warning` from the rejected report was visible in the passing run's output as the tell. Fixed by giving that test a real `UTH` facility fixture and asserting (via the same `wait_until` pattern) that a case actually gets created; added a matching "unresolvable report creates nothing" case alongside it.

**Status:** done and `mix test`-verified — 183 tests, 0 failures, including the real Producer → Pipeline → DB path (not mocked). Iteration 2's first slice (inbound SMS reporting via Broadway) is closed. Known gaps stay as logged above: no USSD session flow, no live Africa's Talking account, no error reply to the sender, by-district aggregation, role-gated case status transitions, reporter identity in the case list.

---

## Iteration 2 — GIS Mapping (slice 2)

**Goal:** the brief's third architecturally-novel piece for this iteration (alongside inbound SMS and the dashboard already built) — a map view of cases by facility. Smallest useful cut: plot a marker per facility (sized by case count) on a Leaflet map, live via the existing `"cases"` PubSub topic. Explicitly not hotspot detection (real spatial clustering) or district/province boundary overlays (needs real GeoJSON boundary data) — both are content/algorithm problems bigger than this cut, deferred and logged below, not silently attempted.

**Decisions:**

- `Facility` gained plain `latitude`/`longitude` floats, not a PostGIS `geography(Point)` column - even though Section 6 of the brief names `geo_postgis` as the committed choice for this module. The reasoning: this slice's only spatial need is "put a point on a map," which floats handle completely; `geo_postgis` only earns its keep once real spatial SQL (containment, distance, clustering) is needed, which is exactly what's deferred. Adding it now would be designing ahead of the iteration that needs it - the same call Iteration 0 already made once for Facility's geospatial column, and the same "small later migration beats speculative upfront complexity" preference this project keeps making (Scope/user_id in Iteration 0, `district_id` staying uncast through Iterations 1-2). Revisit when hotspot detection or boundary-containment queries are actually built.
- Both columns are nullable, not required. There's still no facility-management UI (facilities only come from seeds/fixtures/tests) - a facility without known coordinates should still be creatable, it just won't appear on the map. `Geography.list_facilities_with_coordinates/0` (not `list_facilities/0` filtered in the LiveView) owns "has coordinates" as a query, keeping that decision in the context that owns facility data (Information Expert), not scattered into `MapLive.Index`.
- Leaflet loaded via CDN (`unpkg`, pinned to 1.9.4 with a subresource-integrity hash - verified against leafletjs.com's own download page, not assumed from memory) rather than through esbuild/npm. This project has no `package.json`/`node_modules` - `assets/js/app.js` vendors small utilities by hand (`vendor/topbar.js`) but Leaflet's CSS-plus-marker-icon-image footprint is more than worth hand-vendoring for a first cut. Loaded globally in `root.html.heex` rather than per-route, since only one page uses it and conditional per-route layouts aren't worth building for that.
- The map hook is a **colocated** JS hook (`Phoenix.LiveView.ColocatedHook`, per `AGENTS.md`'s documented convention), not a separate file under `assets/js/hooks/` - this is the first LiveView in the project with any real client-side JS interop, so it's also the first real exercise of that convention beyond `AGENTS.md`'s own short example.
- Server pushes one `"map:update"` event (`push_event/3`, only when `connected?(socket)`, same convention as every other connected-only behavior in this project) carrying every mapped facility's name/coordinates/case count; the hook clears and redraws all markers on every update rather than diffing. Same "recompute everything, simplicity over incremental" call already made for `EpidemiologyLive.Index`'s stats and `MapLive.Index` reuses `CaseManagement.count_cases_by_facility/0` outright rather than re-deriving facility case counts a second way.
- One marker per facility (case *count* sized by radius), not one marker per case. A true density/hotspot view (per-case points, real clustering) is explicitly the deferred "hotspot detection" brief item, not something this cut half-attempts.

**Built:**

- [x] Migration: `facilities.latitude`/`longitude` (nullable floats).
- [x] `Facility.changeset/2` accepts and range-validates them; `Geography.list_facilities_with_coordinates/0`.
- [x] Seed data (`priv/repo/seeds.exs`) updated with approximate town-centre coordinates for all four seeded facilities (demo data, not surveyed).
- [x] `MapLive.Index` at `/map`, same `require_authenticated_user` live_session as `/cases`/`/epidemiology`.
- [x] Leaflet 1.9.4 via CDN in `root.html.heex`; a colocated `.Map` hook rendering circle markers sized by case count, with popups, auto-fit bounds, and a Zambia-centered fallback view when there are no markers yet.

**Gotchas / known test-coverage gap:**

- No automated test covers the actual `push_event` payload or anything the Leaflet hook does client-side - `mix test` can't drive a real browser, and this session couldn't confirm a reliable, verified Phoenix LiveViewTest helper for asserting on a server-pushed event's content (same "don't guess at an API I can't check against live docs" caution as Broadway, applied by *not* writing a test that might be silently wrong rather than by writing one). What **is** tested: the auth redirect, the empty-vs-populated container HTML (a real, if shallow, signal that `list_facilities_with_coordinates/0` is wired in correctly), and the underlying data functions (`list_facilities_with_coordinates/0`, coordinate validation) in `geography_test.exs`. The real check for this slice is opening `/map` in a browser after seeding - flagged plainly rather than claimed as covered.
- This is also the first non-trivial use of `AGENTS.md`'s colocated-hook convention in this project (its own doc example is a one-line phone-number formatter) - if `mix test`/compilation turns up a colocated-hook-specific error, that's the most likely place, same spirit as the Broadway flag last slice.
- First in-browser check hit `/map` showing "No facilities have a known location yet" despite `priv/repo/seeds.exs` listing coordinates for all four facilities. Root cause: the `mix ecto.reset` run earlier (Iteration 2's SMS slice, to pick up the `code` column) reseeded facilities *before* this slice added `latitude`/`longitude` to the seed script - so those rows already existed by name when the seed script gained the new fields, and its `unless Repo.get_by(Facility, name: ...)` guard skipped them rather than backfilling. Same reset also explains a separate symptom hit while debugging this: the dev browser session's login stopped working because `ecto.reset` wipes `users` along with everything else, and the browser's session cookie kept referencing a `user_token` that no longer existed anywhere - re-registering fixed the login side. Fixed the seed script itself instead of reaching for `mix ecto.reset` again (which would have re-broken login): the facility loop now upserts by name (`Repo.get_by` -> `Geography.update_facility/2` if found, `create_facility/1` if not), so `mix run priv/repo/seeds.exs` alone backfills new fields onto existing rows without touching `users`. Worth remembering for any future field added to seed data: the skip-if-exists guard pattern only backfills on a full reset, which gets more disruptive to redo every time (it now means "lose your login too").

**Status:** `mix test`-verified (192 tests, 0 failures). Visually confirmed in-browser for the auth-redirect and empty-state paths and for the Epidemiology Dashboard's live PubSub refresh (same mechanism `/map` uses). The populated-marker path itself - actual pins rendering and moving live on `/map` - was blocked by the coordinate-backfill gotcha above and is pending a re-check after re-running the now-fixed `priv/repo/seeds.exs`. Iteration 2's second slice is otherwise closed. Known gaps stay as logged above: no hotspot detection, no district/province boundary overlays, no automated coverage of the `push_event`/Leaflet-hook payload itself.

---

## Iteration 2 — Predictive Analytics (slice 3)

**Goal:** the brief's last major untouched pillar (alongside SMS/USSD reporting and GIS Mapping, both now built) - some form of outbreak risk prediction. Smallest useful cut: a per-facility risk read, computed from the case data already in this system rather than a trained model, surfaced on its own `/risk` page, live via the existing `"cases"` PubSub topic - proving the module boundary and a first real numeric computation, not delivering the brief's actual "ML model trained on WHO/MOH data" yet (deferred and logged below, not silently attempted).

**Decisions:**

- Scored by *facility*, not district, even though the brief names this module "district-level outbreak risk scoring." Same reason `EpidemiologyLive.Index` and `MapLive.Index` both stayed at facility granularity: `Facility.district_id` still isn't cast anywhere, so there's nothing real to group by district yet. This is the one gap this slice shares with two others already logged - closing it (wiring `district_id`) is explicitly next on the list after this slice, not folded in here.
- A statistical trend heuristic, not a trained ML model. The brief's own Section 6.2 admits the real model depends on historical WHO/MOH data this project doesn't have loaded anywhere, and Section 6 treats "stay in Elixir" (Nx/Axon/Explorer) as a stretch goal, not a given. Building toward a real classifier before there's a real dataset to train it on would be guessing at both the data shape and the accuracy - so this slice scores risk the way the data actually available supports: a linear trend over the last four weeks of *reported* case counts per facility (least-squares slope via Nx), tiered into `:insufficient_data` / `:stable` / `:elevated`. Real, not decorative - genuine arithmetic over genuine data - but a heuristic, not a prediction, and described as exactly that in the UI copy itself so it's never mistaken for more than it is.
- Nx only, no Axon and no external Python/Flask microservice. A linear-regression slope needs nothing more than Nx's core tensor arithmetic (`tensor/2`, `mean/1`, `subtract/2`, `multiply/2`, `pow/2`, `sum/1`, `divide/2`, `to_number/1`) - Axon (neural nets) and a separate Flask service are both real, heavier architectural commitments the brief itself only asks for once there's a trained model to justify them. Nx's default backend needs no compiled NIF/EXLA setup, so this doesn't add any native-build risk on the Windows dev machine either.
- `PredictiveAnalytics` is its own context, not folded into `CaseManagement` despite reading only `CaseManagement`/`Geography` data. Interpreting case counts as a *risk* is a distinct responsibility from owning and counting cases (Information Expert: `CaseManagement` answers "how many", this context answers "is that trending up") - the same module split the brief itself draws between Disease Surveillance and Predictive Analytics. Neither `CaseManagement` nor `Geography` knows this context exists.
- `CaseManagement.count_cases_by_facility_between/2` is a new, deliberately general primitive (an arbitrary `[start, end)` window, not "the last N days") rather than something Predictive-Analytics-specific bolted onto `CaseManagement`'s public API - same "the context that owns the data answers windowed questions about it" reasoning as every other aggregate function already there. Uses `inserted_at` as "when the case was reported," the same proxy `list_cases/0`'s ordering already relies on - there's no separate "when the outbreak actually started" field on `Case`.
- Two tiers of risk (`:stable`/`:elevated`), plus `:insufficient_data` for a facility with zero cases across the whole four-week window - not three real tiers with a "critical" cutoff. There's no real case-volume history yet at this project's dev/demo scale to calibrate a second threshold against, and a made-up one would be worse than not having it. `list_risk_scores/1` takes `now` as an explicit, defaulted argument (not always `DateTime.utc_now/0` internally) specifically so this could be tested deterministically - same reasoning as `MapLive.Index`'s connected-only push pattern, applied to time instead of connection state.
- `/risk`, like `/epidemiology` and `/map`, sits behind login in the same `live_session :require_authenticated_user` - still no separate public-facing route or auth model, same reasoning logged for both of those.

**Built:**

- [x] `mix.exs` gains `{:nx, "~> 0.9"}`.
- [x] `CaseManagement.count_cases_by_facility_between/2` - windowed, facility-grouped case counts.
- [x] `PredictiveAnalytics` context + `RiskScore` struct (computed, not persisted - no migration, no schema) - `list_risk_scores/1`, a four-week trend slope via Nx, tiered into `:insufficient_data`/`:stable`/`:elevated`.
- [x] `RiskLive.Index` at `/risk`, same `require_authenticated_user` live_session as `/cases`/`/epidemiology`/`/map`, live via the `"cases"` PubSub topic - a table of facility, four-week counts, this week's count, trend slope, and risk tier, with an explicit UI note that this is a heuristic, not a trained prediction.

**Gotchas:**

- First dependency this session added on Nx specifically, with the same caveat already logged for Broadway and Oban when they were new: this sandbox still has no route to `hex.pm`/hexdocs, so Nx's exact current API couldn't be checked against live docs before writing against it. Kept deliberately to Nx's smallest, longest-stable numeric surface (`tensor/2`, `mean/1`, `subtract/2`, `multiply/2`, `pow/2`, `sum/1`, `divide/2`, `to_number/1`) to minimize that risk, and used the explicit `{:f, 32}` type-tuple form for `Nx.tensor/2`'s `:type` option rather than a shorthand atom (`:f32`) this session couldn't verify is supported by the resolved version. If `mix test`/compilation fails on anything Nx-shaped, `PredictiveAnalytics.trend_slope/1` is the first place to look.
- Tests pin `now` explicitly (`list_risk_scores/1`'s optional argument) and force-set `inserted_at` on fixture-created cases via `Ecto.Changeset.change/2` + `Repo.update!/1` (not castable through `Case.changeset/2` normally) to land cases deterministically inside specific weekly buckets - same "test manipulates a normally-uncastable field directly" technique, not a new one for this project.
- First real test run (203 tests, 1 failure) found a genuine bug, not just a flaky test: `RiskLive.IndexTest`'s live-update case landed in the DB and broadcast correctly, but the re-rendered page still showed the pre-case stats. Root cause: the most recent weekly bucket's end boundary is `now` itself, compared with a strict `<` (`count_cases_by_facility_between/2`'s half-open `[start, end)` window) - and `Case.inserted_at` is a `:utc_datetime` column (second precision), not microsecond. `RiskLive.Index` recomputes off the very next `{:created, _}` broadcast, which in a test (and plausibly for real, e.g. an SMS webhook's case landing seconds before someone has `/risk` open) can truncate to the *exact same second* as the query's own `now` - and "equal" fails "strictly less than", silently dropping the case that was just reported from its own "this week" bucket. This wasn't caught by `PredictiveAnalyticsTest`'s own unit tests because they all pin `now` and place cases a comfortable 3 days inside each bucket, nowhere near an edge - a reminder that a hand-picked test datetime can hide exactly the boundary case a live, wall-clock-driven caller will actually hit. Fixed in `weekly_buckets/1` by padding `now` forward to the next whole second before any bucket math runs, rather than changing `count_cases_by_facility_between/2`'s comparison to `<=` (which would have fixed this one edge but made adjacent weekly buckets double-count a case landing exactly on *their* shared boundary instead).

**Status:** `mix test`-verified (203 tests, 0 failures, after the boundary-bug fix logged above). Iteration 2's third slice is closed. Known gaps stay as logged above: not a trained model (no historical WHO/MOH dataset), facility- not district-level scoring (pending the district_id gap below), no vaccination/environmental inputs (those modules don't exist yet), only two risk tiers (no real volume data yet to calibrate a third). Iteration 2 as a whole - SMS/USSD reporting, GIS Mapping, and Predictive Analytics, the brief's three architecturally-novel pillars alongside what Iteration 1 already built - is now closed. Next: close the logged Iteration 1 gaps (by-district aggregation, role-gated case status transitions, reporter identity in the case list).

---

## Iteration 3 — Closing logged gaps: by-district aggregation

**Goal:** the first of three gaps carried forward from Iteration 1 (by-district aggregation, role-gated case status transitions, reporter identity in the case list - the other two are still open, picked up one at a time rather than as one large slice). Iteration 1's Epidemiology Dashboard explicitly deferred counts by district because `Facility.district_id` was a column with no changeset field and no way to ever be set; this slice closes exactly that, no more and no less.

**Decisions:**

- `district_id` needed no migration - it's been a real column with a real `references(:districts, on_delete: :nothing, type: :binary_id)` foreign key since Iteration 0's original `create_facilities` migration (confirmed by reading that migration directly rather than assuming). The entire gap was one layer up: `Facility.changeset/2` never cast it, so nothing could ever set it. This slice is `cast`/`foreign_key_constraint` plus the aggregation logic that reads it - deliberately not a bigger schema change.
- `district_id` stays optional on the changeset, same reasoning as `latitude`/`longitude`: there's still no facility-management UI, only seeds/fixtures create facilities, so a facility without a known district should still be creatable rather than blocked on data that doesn't exist yet for it.
- By-district counts are composed in `EpidemiologyLive.Index` itself (`Geography.list_facilities/0`'s `district_id` field + `Geography.list_districts/0` for names + `CaseManagement.count_cases_by_facility/0`'s counts, summed in memory), not a new `CaseManagement`/`Geography` function. Exactly the same "context stays name/grouping-agnostic, caller composes" split already used for by-facility on this same page - no new cross-context coupling introduced to close this gap.
- A facility with cases but no `district_id` set contributes to `@total_cases` and `@by_facility` (it's a real reported case) but to no entry in `@by_district` - not folded into a manufactured "unknown district" bucket. This is the exact trap the by-district aggregate was originally deferred over (Iteration 1's dashboard decisions log it explicitly), now avoided by construction rather than revisited and re-risked.
- Scope stays to the Epidemiology Dashboard only - `MapLive.Index` and `RiskLive.Index` both also currently work at facility granularity for their own, separately-logged reasons (no district boundary GeoJSON for the map; no district-level trend design decided for risk scoring), and neither is touched here. Widening either of those to district-level is a distinct, larger decision each, not a side effect of closing this specific dashboard gap.
- `priv/repo/seeds.exs` assigns each of the four seeded facilities its real Zambian district (UTH/Kabwata Clinic → Lusaka, Ndola Teaching Hospital → Ndola, Monze Mission Hospital → Monze) via the now-standard upsert pattern (see the GIS Mapping entry above) - `mix run priv/repo/seeds.exs` alone backfills it onto existing rows, no reset needed.

**Built:**

- [x] `Facility.changeset/2` casts `district_id` and validates it with `foreign_key_constraint/2`.
- [x] `priv/repo/seeds.exs` assigns each seeded facility its district.
- [x] `EpidemiologyLive.Index` - a "By district" table (district, case count, busiest first), live via the same `"cases"` PubSub topic as everything else on that page, with its own empty-state message distinct from the by-facility one.

**Gotchas:**

- None new - this slice touched schema/changeset/seed/LiveView code already well-trodden by prior slices, no new library or infrastructure risk introduced.

**Status:** `mix test`-verified (208 tests, 0 failures). By-district aggregation is closed. Remaining Iteration 1 gaps: role-gated case status transitions, reporter identity in the case list.

---

## Iteration 3 — Closing logged gaps: role-gated case status transitions

**Goal:** the second of the three gaps carried forward from Iteration 1. `update_case_status/2` has existed and been tested since Iteration 1, but `CaseLive.Index` deliberately shipped with no confirm/resolve controls at all, because there was no role-based workflow yet to decide who's allowed to move a case through its lifecycle. This slice adds exactly that control, at the smallest useful grain: any user with *an* assigned role can advance a case one step; which of the three roles may do what is explicitly not decided here (see below).

**Decisions:**

- `CaseManagement.next_status/1` encodes the one-directional lifecycle (`:suspected -> :confirmed -> :resolved -> nil`) as a lookup, layered on top of `update_case_status/2` rather than tightening `Case.status_changeset/2` itself. Iteration 1 deliberately left the changeset permissive (any valid status from any other) because there was no screen yet to make a stricter rule meaningful; now that `CaseLive.Index` has one, the stricter rule lives in the one place that needs it, so a future consumer that legitimately needs to set an arbitrary status (a correction, a data-migration script) still can.
- `CaseManagement.advance_case_status/2` takes a plain `role` atom (or `nil`), not an `%Accounts.User{}` struct - `CaseManagement` stays decoupled from `Accounts`'s schema the same way it already is from `Geography.Facility`'s (no cross-context struct aliasing anywhere in this project so far). `CaseLive.Index` is what bridges the two contexts, reading `current_scope.user.role` and passing the bare atom through.
- Authorization is binary at this slice: `role` must be assigned (not `nil`) - any of the three roles qualifies, no distinction between `:health_worker`, `:district_officer`, and `:moh_admin` for who may confirm vs. resolve a case. No real use case has decided that distinction yet (e.g. "only `:moh_admin` may resolve"), and guessing at one would be exactly the kind of speculative rule this project has consistently avoided (role-on-`User` itself in Iteration 0, write-authorization on `Geography` in Iteration 0, disease/status enums needing no metadata in Iteration 1). This is a logged, deliberate gap, not an oversight - revisit once a real workflow need shows up.
- Both checks - role present, case has a next status - are enforced in `CaseManagement.advance_case_status/2` itself, not only in `CaseLive.Index`'s decision to render a button. A forged `"advance_status"` event (bypassing the UI entirely) hits the same two checks a real click does - the same server-side-re-validation precedent `with_reporter/2` already set for `reported_by_id` tampering in Iteration 1.
- `CaseLive.Index`'s `can_advance_status?/2` mirrors the same two checks purely to decide whether to render the button at all - a UI nicety (don't show a dead-end "Confirm" on a resolved case, don't show any button to a roleless user), not a second authorization boundary. `advance_case_status/2` re-checks both regardless of what the UI shows or hides.
- The button relies on the existing PubSub round-trip rather than a manual `stream_insert` in the event handler's success branch: `advance_case_status/2` broadcasts `{:updated, case}` through the same `"cases"` topic every other mutation in this project already uses, which lands right back on this LiveView's own `handle_info({:updated, _}, _)`. Same "don't special-case the mutating client" pattern `handle_event("save", ...)` already uses for newly-created cases.
- There's still no self-service or admin UI to assign a role to a user - `Accounts.assign_user_role/2` has existed since Iteration 0 but nothing calls it outside `iex`. That's a real, separately-logged gap (role assignment itself), not something this slice's job to close; it's the reason this slice's buttons won't appear for anyone until a role is assigned by hand. Revisit once there's a real use case for self-service role requests or admin approval - not guessed at here, same as every other not-yet-needed piece in this log.

**Built:**

- [x] `CaseManagement.next_status/1` - `:suspected -> :confirmed -> :resolved -> nil`.
- [x] `CaseManagement.advance_case_status/2` - `{:ok, case}` / `{:error, :unauthorized}` / `{:error, :no_next_status}`.
- [x] `CaseLive.Index` - an "Actions" column with a Confirm/Resolve button (rendered only when the current user has a role and the case has a next status), a `handle_event("advance_status", ...)` that calls `advance_case_status/2` and flashes success or the specific rejection reason, and `can_advance_status?/2`/`advance_label/1` helpers.
- [x] Tests: `CaseManagement.next_status/1` and `advance_case_status/2` (success, `:unauthorized`, `:no_next_status`) in `case_management_test.exs`; button visibility across roleless/role-assigned/resolved cases, the success path, and two forged-event cases (no role, already-resolved) in `case_live/index_test.exs`.

**Gotchas:**

- `<.button type="button" ...>` triggered a compile warning (`undefined attribute "type"`) - `CoreComponents.button/1`'s `:rest` global attr has an explicit `include:` allowlist (`href navigate patch method download name value disabled`) that `type` isn't part of, so it's rejected rather than passed through. Not actually needed here anyway (the button isn't inside the report `<.form>`, so there's no accidental-submit risk `type="button"` would guard against) - dropped it rather than widening the shared component's allowlist for one caller.
- First real `mix test` run (222 tests, 3 failures) found real test bugs, not production bugs - worth logging since two of the three are the same category of mistake and easy to repeat:
  - Two button-visibility tests asserted `refute html =~ "Confirm"` / `refute html =~ "Resolve"` against the *whole page's* HTML - but the status badge right next to the button renders "Confirmed"/"Resolved", and `"Confirmed"` contains `"Confirm"` as a substring (same for `"Resolved"`/`"Resolve"`). The refutation was tripping over the badge text, not the button. Fixed by scoping the check to the actual element with `has_element?(lv, "button", "Resolve")` (Floki-backed, matches only `<button>` elements) instead of a raw substring match on the full rendered page - the same fix applies to any future assertion pairing a status label with an action label that's a prefix of it.
  - The "clicking the action button" test asserted on `render_click/1`'s own return value for the *post-click* status - but `advance_case_status/2` updates the stream only via the `{:updated, case}` PubSub broadcast landing back on this same LiveView's `handle_info/2`, which happens *after* `handle_event/3` has already replied with the click's diff (see the code comment on `handle_event("advance_status", ...)`). `render_click/1`'s return only reflects what `handle_event/3` itself changed (the flash), not what a subsequent `handle_info/2` does. Fixed by re-rendering (`has_element?(lv, ...)` again after the click) rather than asserting on the click's own return - the same ordering the existing "broadcasts a newly reported case to other viewers live" test already relies on, just applied to a LiveView updating itself via its own broadcast instead of a second viewer's.
- Operational, not a code gotcha: testing this in-browser needs a role on your own account first, and there's no UI for that yet (see the decision above). From `iex -S mix`:

  ```elixir
  alias ZamHealthWatch.Accounts
  user = Accounts.get_user_by_email("philsamakayi@gmail.com")
  Accounts.assign_user_role(user, %{role: :district_officer})
  ```

  An already-open browser tab's LiveView won't pick up the new role until the page is reloaded - `current_scope` is captured once, at mount/connect time, not re-read live.

**Status:** `mix test`-verified (222 tests, 0 failures) after fixing the three test bugs above (production code was correct on the first run - all three failures were in the new tests themselves). Role-gated case status transitions is closed. Remaining Iteration 1 gap: reporter identity in the case list.

---

## Iteration 3 — Closing logged gaps: reporter identity in the case list

**Goal:** the last of the three gaps carried forward from Iteration 1. `CaseLive.Index`'s list has shown every case's disease, facility, and status since Iteration 1, but never *who* reported it - `Accounts` had no lookup-by-id-for-display function and this slice didn't need one at the time. Now that one's needed, this closes it: a "Reported by" column, nothing more.

**Decisions:**

- `Accounts.list_users/0` is a plain `Repo.all(User)` - it returns full `%User{}` structs, not a display-ready map, same "context stays name/format-agnostic, caller composes" split `Geography.list_facilities/0` already established for `facilities_by_id`. `Accounts` doesn't get to guess whether a consumer wants an email, a phone number, or something else entirely.
- The display choice - email for a web-registered user, phone for an SMS-only one (`User.email` went nullable in Iteration 2's SmsReporting slice specifically because an SMS reporter has no email) - lives in `CaseLive.Index` as a private `reporter_label/1`, not in `Accounts`. Same reasoning as `disease_label/1` and `status_badge_class/1` already living in the LiveView rather than the context.
- `@reporters_by_id` is composed once in `mount/3` (`Map.new(Accounts.list_users(), &{&1.id, reporter_label(&1)})`), exactly mirroring `@facilities_by_id`'s existing pattern - including that pattern's one known limitation: it's a point-in-time snapshot, not live-updated. A user who registers (or an SMS reporter created for the first time) *after* another viewer's page has already mounted won't have their name resolved by that viewer's `@reporters_by_id` until a reload - the newly reported case still appears live via the existing `{:created, _}` broadcast, just attributed to "Unknown reporter" until then. This is the exact same trade-off `@facilities_by_id` already carries for a facility created mid-session; not new to this slice, just newly visible because `@reporters_by_id` is built the same way. Revisit both together if this ever becomes a real problem (e.g. subscribing to an `Accounts`-side broadcast too) - no evidence yet that it is one.
- No column for the reporter's *role* or facility, only their identity (email/phone) - nothing in this slice's use case (attributing a report to a person) calls for either, and guessing at a use case for them would repeat the mistake this whole log has consistently avoided.

**Built:**

- [x] `Accounts.list_users/0`.
- [x] `CaseLive.Index` - a "Reported by" column (between Facility and Status) showing the reporter's email or phone via `@reporters_by_id`/`reporter_label/1`, falling back to "Unknown reporter" the same way `@facilities_by_id` already falls back to "Unknown facility".
- [x] Tests: `Accounts.list_users/0` in `accounts_test.exs`; the column showing a web reporter's email and an SMS reporter's phone in `case_live/index_test.exs`.

**Gotchas:**

- This slice's own production code needed nothing new (a direct copy of the `@facilities_by_id` pattern already proven in Iteration 1), but re-running the full suite alongside it surfaced a genuine, pre-existing test-isolation gap in the *previous* slice's tests (role-gated status transitions), not in this one - worth logging here since it's what running `mix test` for this slice actually found:
  - One run (224 tests, 1 failure) failed `case_live/index_test.exs`'s "shows a Resolve button for a confirmed case when the user has a role" - `refute has_element?(lv, "button", "Confirm")` found a `"Confirm"` button that shouldn't have existed for that test's own single case. Root cause: `async: true` means many tests' LiveViews are mounted concurrently, and `CaseManagement.subscribe_cases()`/`broadcast_case/1` use one fixed, global `"cases"` PubSub topic with no per-test scoping - unlike `Repo` queries, which Ecto's SQL Sandbox isolates per test via a real transaction. A `{:created, _}`/`{:updated, _}` broadcast from a *different*, concurrently-running test's case (its own, wholly separate sandboxed transaction) still lands on every other connected LiveView's `handle_info/2`, including this test's, and gets `stream_insert`ed into a page that test never created that row on. A page-wide check like `has_element?(lv, "button", "Confirm")` (or the plain-substring checks before it) can't distinguish "this test's own row" from "some other test's row that leaked in via PubSub."
  - This was a latent risk since Iteration 1 first wrote a PubSub-driven LiveView test (the same global-topic broadcast underlies every `"cases"` subscriber in this project), not something this or the previous slice introduced - it just hadn't been caught before, because every prior assertion happened to check something specific enough (a uniquely-named facility, an exact flash message) to never collide with another concurrently-running test's data. Generic action-button labels ("Confirm"/"Resolve") were the first assertions in this project without that natural uniqueness.
  - Fixed by scoping every action-button assertion in `case_live/index_test.exs`'s "case status transitions" describe block to that test's own case, via a `row_selector/1` test helper (`"#cases-#{case.id}"`, Phoenix's own `stream/3` DOM id) - `has_element?(lv, row_selector(case) <> " button", "Resolve")` instead of `has_element?(lv, "button", "Resolve")`. Not fixed at the application level (e.g. per-test PubSub topic scoping) - that's a bigger, genuinely separate concern (it would touch `CaseManagement`'s public API, not just this test file) with no real use case yet pushing for it, the same "don't build infrastructure before something needs it" call this log keeps making elsewhere. Worth remembering for *any* future test asserting on a PubSub-driven LiveView's rendered content by generic text rather than by a row/element scoped to that test's own data.

**Status:** `mix test`-verified (224 tests, 0 failures) after the cross-test PubSub scoping fix above (production code for this slice needed no changes). All three gaps logged at the close of Iteration 1 (by-district aggregation, role-gated case status transitions, reporter identity in the case list) are closed.

---

## Iteration 4 — Role assignment UI

**Goal:** a small enabling slice ahead of Construction proper (Lab Reporting, Vaccination, Drug Availability, Hospital Capacity - the brief's four remaining lower-risk modules), chosen over starting one of those because it closes a real, already-biting gap rather than opening a new one: role-gated case status transitions shipped in Iteration 3, but the only way to actually grant a role was a raw `iex -S mix` snippet (logged as an "operational, not a code gotcha" note in that iteration). Construction's modules will each want role-specific behavior of their own sooner or later - this is also the natural place to prove that out once, rather than each module re-deciding it. Smallest useful cut: list every registered user, assign a role and (optionally) a facility, gated to `:moh_admin` only.

**Decisions:**

- No new schema or migration - `role`/`facility_id` on `User`, `Accounts.change_user_role/2`/`assign_user_role/2`, and `User.role_changeset/2` have all existed since Iteration 0. This slice is entirely a missing screen over an already-built, already-tested domain layer.
- Gated to `:moh_admin` specifically, not "any assigned role" - this is the first place in the project with a real, specific-role authorization need. Every earlier "no role check yet" decision (Geography's writes in Iteration 0, case reporting in Iteration 1, the case list itself) stayed deliberately permissive because nothing needed otherwise; letting any logged-in user, or any role, manage everyone else's role would be a real privilege-escalation hole, not a "no use case yet" deferral. `UserAuth.on_mount(:require_moh_admin, ...)` composes on top of the existing `:require_authenticated` clause (calls it, then adds the role check) rather than duplicating its session/redirect logic - the only new behavior is the role check once a user is confirmed logged in. A new `live_session :require_moh_admin` in the router, not folded into `:require_authenticated_user` (`AGENTS.md`: never duplicate a live_session name), since its on_mount chain is strictly more restrictive than the shared one.
- Facility assignment is bundled into the same form as role, not deferred to a later slice - `User.role_changeset/2` already casts both together (an Iteration 0 decision), and `AdminLive.Index` is the first and only screen that will ever drive that changeset, so splitting the UI in two would just re-implement the same two-field form twice for no real reason.
- The bootstrap problem: everything on `/admin/users` is gated behind an existing `:moh_admin`, so the very first admin can't come from this page - the same chicken-and-egg Iteration 3's gotcha log already named. `priv/repo/seeds.exs` now bootstraps `philsamakayi@gmail.com` (the developer's own account) to `:moh_admin` if that account exists and has no role yet, guarded on `role: nil` so re-running the script never clobbers a role changed since through the real UI. This replaces the manual `iex` snippet as *how the first admin gets minted*; `/admin/users` is how every role after that gets managed. A real product would need a proper first-admin flow (an invite, an env-var-configured bootstrap email, whatever) - hardcoding one personal email in seed data is a portfolio-project shortcut, not something meant to generalize past this one deployment.
- No PubSub broadcast on role assignment, and `@users`/`@forms` are plain assigns recomputed locally after each mutation, not a `stream/3` - nothing else in the app needs to react live to a role change yet (unlike `"cases"`, which three other LiveViews already subscribe to), so there's no topic to broadcast on. Revisit if a future consumer needs to know when a role changes.
- `role_label/1` looks the display string up in `@role_options` rather than calling `Phoenix.Naming.humanize/1` directly on the row - same move `CaseLive.Index.disease_label/1` already made, and for the same reason: humanize's one-capital-letter, underscore-to-space rule turns `:moh_admin` into "Moh admin", not the acronym-cased "MOH admin" the dropdown option already spells out correctly.
- Each row gets its own `<.form>` (role select + facility select + Save button, all inside one `<td>` - valid HTML, a form doesn't have to span the whole `<tr>`) rather than a shared page-level form or a separate per-user edit route. Matches this project's running "smallest useful cut" preference (`CaseLive.Index` keeps its report form and list on one page too) over a `phx-change`-on-select auto-save, which would silently commit a role change without an explicit confirming action - a real Save button reads better for something this consequential.
- `<.table>`'s `row_id` is passed explicitly (`&"user-#{&1.id}"`) even though `@users` is a plain list, not a `LiveStream` - the component only derives a row id automatically for streams, and a stable per-row DOM id is what every other row-scoped test assertion in this project (`CaseLive.IndexTest`'s `row_selector/1`) already relies on being there.

**Built:**

- [x] `UserAuth.on_mount(:require_moh_admin, ...)` - authenticates, then requires `current_scope.user.role == :moh_admin`; redirects to `/users/log-in` if not logged in (same message as `:require_authenticated`) or to `/` with a permission-error flash if logged in but not an admin.
- [x] Router: `live_session :require_moh_admin` -> `GET /admin/users`.
- [x] `AdminLive.Index` - lists every user (`Accounts.list_users/0`, sorted by email/phone) with their current role and facility, and a per-row form to assign both via `Accounts.assign_user_role/2`. Handles the "role required" validation failure (e.g. trying to clear an already-assigned role) with a flash error and the row's form redisplaying the attempted (invalid) state.
- [x] `priv/repo/seeds.exs`: idempotent `philsamakayi@gmail.com` -> `:moh_admin` bootstrap.
- [x] Tests: `UserAuthTest`'s new `on_mount :require_moh_admin` describe block (admin allowed; a different role, no role, and no session all halted with the right flash/redirect); `AdminLive.IndexTest` covering route access control, the listing (email vs. SMS-phone identity, "Unassigned", current facility or a dash), and assigning a role alone, a role + facility together, changing an existing role, and rejecting an attempt to clear one.

**Status:** `mix test`-verified (240 tests, 0 failures) - clean first run, no fixes needed. Iteration 4 is closed. Next: pick the first Construction-phase module (Laboratory Reporting, Vaccination Monitoring, Drug Availability, or Hospital Capacity).

---

## Iteration 5 — Construction: Laboratory Reporting

**Goal:** the first of the brief's four remaining, lower-risk Construction modules. Chosen over Vaccination/Drug/Hospital for narrative value, not lower risk (all four are similarly schema-shaped, no new architectural pattern) - it closes the loop the brief itself calls out: "lab test requests and results, linked back to cases; confirms or downgrades surveillance signals." Smallest useful cut: request a lab test against an existing case, record one of three results, and have a positive/negative result actually move the case's status - proving real surveillance value, not just another disconnected schema next to `cases`.

**Decisions:**

- `LabReporting` is its own context, not folded into `CaseManagement` the way Disease Surveillance's aggregates were in Iteration 1. That fold was justified there because there was no distinct schema or responsibility yet to split on; a lab test *is* a distinct entity with its own two-state lifecycle (`:pending` -> `:resulted`, unlike `Case`'s three-state one), so it clears the bar Iteration 1 itself set for when splitting is warranted. `CaseManagement` doesn't know `LabReporting` exists; `LabReporting` depends on `CaseManagement`'s public API (`get_case!/1`, `update_case_status/2`) in one direction only - the same direction `PredictiveAnalytics` already depends on it and `Geography`.
- Two states, not three - no "sample collected"/"in progress" step. Nothing in this project talks to a real lab system yet (no LIS integration, no barcode/sample-tracking use case), so a test is either awaiting a result or has one. A finer workflow would be designing ahead of a use case that doesn't exist yet, same call this project keeps making for every other not-yet-needed distinction.
- What a result does to the linked case is `LabReporting`'s call, not `CaseManagement`'s (Information Expert: this context knows what a lab result *means* for surveillance, the same split `PredictiveAnalytics` already draws for what a case-count trend means) - `:positive` confirms (`:confirmed`), `:negative` downgrades/rules out (`:resolved`), `:inconclusive` changes nothing. Applied via `CaseManagement.update_case_status/2` unconditionally, regardless of the case's *current* status - same "no stricter transition rule than the data layer already allows" call Iteration 1 made for `Case.status_changeset/2` itself. A result landing on an already-`:resolved` case (e.g. a health worker closed it before the lab confirmed it) will reopen or re-close it rather than being silently ignored - tested explicitly (see Built) and logged here as a deliberate, known limitation rather than a guessed-at rule with no real second-order use case behind it yet.
- Recording a result is role-gated (`role` must be assigned, any of the three qualifies - same "no finer distinction has a real use case yet" call `advance_case_status/2` made); *requesting* a test is not, same "every authenticated user can act, no use case for narrower yet" call case reporting made in Iteration 1. The asymmetry is deliberate, not an oversight: a result can change a case's status exactly the way the case list's own Confirm/Resolve buttons can, so leaving that path ungated while the button is gated would be a real, if narrow, hole - Iteration 4's role-assignment UI is what actually lets this gate mean something now. `record_result/3` also rejects re-recording a result for an already-`:resulted` test (a second, distinct check from the role one), since overwriting a result would also silently re-trigger its case side effect a second time.
- `LabLive.Index` (`/labs`) sits in the same shared `:require_authenticated_user` live_session as `/cases`/`/epidemiology`/`/map`/`/risk`, not the `:require_moh_admin` one - only *recording a result* needs gating, done at the row level (mirrors `CaseLive.Index`'s role-gated advance-status button) exactly the way viewing/using the page as a whole doesn't need admin-only access.
- A separate `"lab_tests"` PubSub topic, not reused from `CaseManagement`'s `"cases"` one - same "each context broadcasts on its own topic" precedent `Geography`'s `"districts"`/`"facilities"` topics already set. `record_result/3`'s case-status side effect still reaches every other `"cases"`-subscribed LiveView for free, via `CaseManagement.update_case_status/2`'s own existing broadcast - nothing extra needed for that.
- `Case.disease_options/0`/`disease_label/1` extracted out of `CaseLive.Index` and `EpidemiologyLive.Index` (which each carried their own identical copy) and onto `CaseManagement.Case` itself, now that `LabLive.Index`'s case picker is a third consumer of the same list - exactly the threshold `EpidemiologyLive.Index`'s own decision log named as the trigger to stop duplicating it ("revisit... once a third consumer needs the same list; two isn't a pattern yet"). Placed on the schema, not the context - Information Expert: `Case` is what declares the valid `disease` values in the first place.
- The case picker on `/labs` lists every case regardless of status, unfiltered - real-world retesting is legitimate, and filtering out `:resolved` cases (or cases that already have a pending test) would be a rule with no real use case behind it yet, same reasoning applied throughout this project.

**Built:**

- [x] Migration: `lab_tests` table (`status`, `result`, `resulted_at`, `case_id`, `requested_by_id`, indexed on `case_id`/`requested_by_id`/`status`).
- [x] `LabReporting` context + `LabTest` schema - `list_lab_tests/0`, `get_lab_test!/1`, `request_test/1`, `change_lab_test/2`, `record_result/3`, PubSub broadcast (`"lab_tests"` topic) on request/result.
- [x] `LabLive.Index` at `/labs` - a request form (pick an existing case) above a live-updating list of lab tests, with role-gated Positive/Negative/Inconclusive buttons per pending row. Tests cover: auth redirect, empty state, listing, requesting a test (valid data, validation error, the server overriding a tampered `requested_by_id`, live broadcast to a second viewer), and recording a result (button visibility by role and by test status, each of the three result values' effect on the linked case - including the deliberate resolved-case-reopens case above, a forged event with no role, a forged event on an already-resulted test, and a forged event with an unrecognized result value).
- [x] `Case.disease_options/0`/`disease_label/1` extraction; `CaseLive.Index`/`EpidemiologyLive.Index` updated to call it instead of keeping their own copies.

**Status:** `mix test`-verified (272 tests, 0 failures) - clean first run, no fixes needed. Iteration 5 is closed. Next: pick the next Construction module (Vaccination Monitoring, Drug Availability, or Hospital Capacity).

---

## Iteration 6 — Construction: Vaccination Monitoring

**Goal:** the brief's "coverage rates by district/antigen/campaign; feeds risk scoring (low coverage = higher outbreak risk)" module. Smallest useful cut: record a coverage submission (doses administered against a target population, for a district/antigen/campaign combination) and show it back with a computed coverage-rate badge - proving the data model holds up, without yet chasing the "feeds risk scoring" half of the brief's sentence (see below for why that's a deliberately separate piece of work).

**Decisions:**

- Coverage is reported directly at *district* level (a `district_id` foreign key straight to `Geography.District`), not aggregated up from per-facility submissions the way `Case`/`LabTest` hang off a `facility_id`. The brief's own phrasing groups this module's data by "district/antigen/campaign", not facility, and Zambia's real EPI reporting already compiles to district level before it reaches anyone this system would show it to. A facility-level submission workflow is a real possible future slice, not a gap this one is pretending doesn't exist.
- `VaccinationMonitoring` is its own context, decoupled from `Geography` and `Accounts` the same way `CaseManagement` and `LabReporting` already are - `foreign_key_constraint/2` on the schema (`district_id`, `reported_by_id`), no cross-context associations, neither `Geography` nor `Accounts` aware this context exists.
- A coverage figure is reported once, not advanced through a lifecycle - there's no "request, then confirm" two-phase workflow the way `LabReporting` has one, because there's no second phase to a coverage number: it either gets corrected by a new submission or it doesn't. One changeset, one `record_vaccination/1`, no editing or deletion yet - same "no rule guessed at without a real use case" reasoning applied everywhere else in this project. Consequently, recording is open to any authenticated user (same as case reporting and lab test requesting) - there's no second, role-gated action on this screen the way `LabLive.Index`'s result-recording buttons need one, so `/vaccinations` needed no route-level or row-level gating at all.
- `antigen` is a fixed `Ecto.Enum` (BCG, OPV, Pentavalent, Measles-Rubella, PCV), with `VaccinationRecord.antigen_options/0`/`antigen_label/1` on the schema from the start - same "single source of truth on the schema, not the LiveView" pattern `Case.disease_options/0`/`disease_label/1` settled into once a third consumer needed it, applied immediately here since the form and table both need it from day one. `campaign`, by contrast, is a plain free-text string, not an enum - unlike antigens (a fixed clinical category), campaigns are arbitrarily named events ("Routine - Sep 2026", "Measles Catch-up 2026") with no closed set to enumerate.
- `coverage_rate/1` lives on `VaccinationRecord` (Information Expert - the schema holding `doses_administered`/`target_population` is what answers "what's the coverage"), computed on read like `PredictiveAnalytics.RiskScore`, never persisted. Deliberately **not** capped at 100% - doses exceeding the target population is a real, meaningful signal (a campaign overshooting its original estimate), not invalid data to clamp away. The 80%/50% badge thresholds are placeholders in the same honestly-flagged-arbitrary spirit as `RiskScore`'s own tier cutoffs, not calibrated against a real Zambia EPI target yet.
- The brief's "feeds risk scoring" half is **deliberately not wired into `PredictiveAnalytics` this slice**, and that's worth being direct about rather than quietly dropping: `PredictiveAnalytics.list_risk_scores/1` is scored per *facility* today, while this module reports per *district* - blending the two needs `PredictiveAnalytics` itself to move to district-level scoring first. That's real, separate work (though `Facility.district_id` finally being castable, as of Iteration 5's `facility.ex` change, unblocks it) - not a quick bolt-on here, and not something to fake by pattern-matching district names against facility names. Logged here as the natural next iteration once this slice is stable.
- Own `"vaccination_records"` PubSub topic, not reused from `"cases"`/`"districts"`/`"lab_tests"` - same per-context topic precedent every other module in this project already set.

**Built:**

- [x] Migration: `vaccination_records` table (`antigen`, `campaign`, `doses_administered`, `target_population`, `district_id`, `reported_by_id`, indexed on `district_id`/`reported_by_id`/`antigen`).
- [x] `VaccinationMonitoring` context + `VaccinationRecord` schema - `list_vaccination_records/0`, `get_vaccination_record!/1`, `record_vaccination/1`, `change_vaccination_record/2`, `antigen_options/0`, `antigen_label/1`, `coverage_rate/1`, PubSub broadcast (`"vaccination_records"` topic) on create.
- [x] `VaccinationLive.Index` at `/vaccinations` - a coverage-submission form (district/antigen/campaign/doses/target) above a live-updating table with a computed coverage-rate badge per row (success/warning/error by the 80%/50% thresholds above).
- [x] Tests: context tests (list, get, record with valid/invalid data - required fields, negative doses, non-positive target, bad `district_id`/`reported_by_id` FKs, broadcast; `coverage_rate/1` including the not-capped-above-100%-case; `antigen_options/0`/`antigen_label/1`); LiveView tests (auth redirect, empty state, listing, recording with valid data, validation error, the server overriding a tampered `reported_by_id`, live broadcast to a second viewer, and each of the three coverage badge tiers).

**Status:** `mix test`-verified (299 tests, 0 failures) - clean first run, no fixes needed. Iteration 6 is closed. Next: pick the next Construction module (Drug Availability or Hospital Capacity), or revisit `PredictiveAnalytics` to move it to district-level scoring so Vaccination Monitoring can actually feed risk scoring per the brief.

---

## Iteration 7 — Construction: Drug Availability

**Goal:** the brief's "stock levels of essential medicines by facility; flags shortages that compound an active outbreak" module. Smallest useful cut: record a stock submission (quantity on hand against a reorder level, for a facility/medicine combination) and flag it as a shortage when quantity falls below the reorder level - the "compound an active outbreak" correlation with live case data is deliberately left for later (see below).

**Decisions:**

- Reported at *facility* level (`facility_id`, not `district_id`) - the brief's own phrasing is "by facility", matching `Case`/`LabTest`'s existing grain rather than `VaccinationMonitoring`'s district-level one from Iteration 6. Different modules, different natural grain by the brief's own wording - no attempt made to force them to match each other.
- `DrugAvailability` is its own context, decoupled from `Geography` and `Accounts` the same way every prior context in this project is - `foreign_key_constraint/2` on the schema (`facility_id`, `reported_by_id`), no cross-context associations.
- Same "reported once, no lifecycle, no editing yet" shape `VaccinationMonitoring` already settled on in Iteration 6, for the same reason: a stock count either gets corrected by a new submission or it doesn't, there's no second phase to advance it through. Consequently, recording is open to any authenticated user, no role gate - there's no second, role-gated action on this screen the way `LabLive.Index`'s result-recording buttons need one.
- `reorder_level` is entered per submission, not looked up from a fixed per-medicine table of "safe stock levels" - real consumption varies enough by facility that a single global threshold per medicine would be a guessed-at rule with no real data behind it. Whoever submits a count is trusted to know what "low" means at their own facility.
- `medicine` is a fixed `Ecto.Enum` scoped to essential medicines that map to this project's five tracked diseases (ORS and IV fluids for cholera, Artemether-Lumefantrine for malaria, Ciprofloxacin and Ceftriaxone for typhoid) rather than a general pharmacy formulary - same "only what a real use case needs" reasoning `Case.disease_options/0` already applies to disease tracking. `DrugStock.medicine_options/0`/`medicine_label/1` on the schema from the start, same pattern `VaccinationRecord.antigen_options/0`/`antigen_label/1` used.
- `DrugStock.shortage?/1` is a computed boolean (Information Expert - the schema holding both numbers answers "is this a shortage"), not a persisted column that could drift out of sync with the two numbers it's derived from. Two states only (Adequate/Shortage), not a graded tier system the way `VaccinationRecord`'s coverage badge has three - "flags shortages" in the brief reads as a binary signal, and a graded early-warning tier would be a rule with no real use case behind it yet.
- The brief's "flags shortages that compound an active outbreak" half is only half built this slice, and that's worth being direct about: nothing here cross-references an active case's disease against the medicine that treats it (e.g. a cholera case at a facility with an ORS shortage). That correlation is real, separate analysis work - deliberately not guessed at here, same call `VaccinationMonitoring` made about its own risk-scoring integration in Iteration 6 rather than bolting on something half-considered.
- Own `"drug_stocks"` PubSub topic, not reused from any other context's - same per-context topic precedent every module in this project has set.
- `time_ago/1` extracted out of `LabLive.Index` and `VaccinationLive.Index` (each carrying an identical private copy) into a new shared `ZamHealthWatchWeb.TimeHelpers` module, now that `DrugLive.Index` is a third consumer of the exact same function - exactly the threshold `Case.disease_options/0`'s own decision log named as the trigger in Iteration 5 ("two isn't a pattern yet"). Imported (`import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]`) rather than aliased, so call sites in all three LiveViews stay unchanged. Given its own direct unit tests (`TimeHelpersTest`) for the first time, since it's no longer a private, only-indirectly-exercised implementation detail of one LiveView.

**Built:**

- [x] Migration: `drug_stocks` table (`medicine`, `quantity_on_hand`, `reorder_level`, `facility_id`, `reported_by_id`, indexed on `facility_id`/`reported_by_id`/`medicine`).
- [x] `DrugAvailability` context + `DrugStock` schema - `list_drug_stocks/0`, `get_drug_stock!/1`, `record_stock/1`, `change_drug_stock/2`, `medicine_options/0`, `medicine_label/1`, `shortage?/1`, PubSub broadcast (`"drug_stocks"` topic) on create.
- [x] `DrugLive.Index` at `/drugs` - a stock-submission form (facility/medicine/quantity/reorder level) above a live-updating table with a computed Adequate/Shortage badge per row.
- [x] `ZamHealthWatchWeb.TimeHelpers.time_ago/1`, extracted from `LabLive.Index`/`VaccinationLive.Index`, now shared by all three LiveViews; `TimeHelpersTest` covering "just now", minutes, hours, and days.
- [x] Tests: context tests (list, get, record with valid/invalid data - required fields, negative quantity, negative reorder level, bad `facility_id`/`reported_by_id` FKs, broadcast; `shortage?/1` both directions; `medicine_options/0`/`medicine_label/1`); LiveView tests (auth redirect, empty state, listing, recording with valid data, validation error, the server overriding a tampered `reported_by_id`, live broadcast to a second viewer, and both badge states).

**Status:** `mix test`-verified (329 tests, 0 failures) - clean first run, no fixes needed. Iteration 7 is closed. Next: Hospital Capacity (the last of the brief's four Construction modules), or revisit `PredictiveAnalytics` to move it to district-level scoring, or build the shortage/active-outbreak correlation this iteration deliberately deferred.

---

## Iteration 8 — Construction: Hospital Capacity

**Goal:** the brief's "bed occupancy, ICU availability, admission rates by facility - the 'can the system absorb this' view" module - the last of the brief's four Construction modules (Laboratory Reporting, Vaccination Monitoring, Drug Availability, Hospital Capacity all now built). Smallest useful cut: record a capacity snapshot (total/occupied beds, ICU beds total/occupied, today's admissions) for a facility and flag it Adequate/Near capacity/Over capacity by bed occupancy.

**Decisions:**

- Reported at *facility* level (`facility_id`), same grain as `Case`/`LabTest`/`DrugStock` - the brief's own phrasing is "by facility". Unlike `VaccinationMonitoring`'s genuine district/facility mismatch with `PredictiveAnalytics.list_risk_scores/1` (which scores per facility today), this module's grain already matches - a real, comparatively easy future integration, still deliberately not built this slice (see below).
- `HospitalCapacity` is its own context, decoupled from `Geography` and `Accounts` the same way every prior context in this project is.
- Same "reported once, no lifecycle, no editing yet, open to any authenticated user, no role gate" shape `VaccinationMonitoring` and `DrugAvailability` already settled on - a capacity snapshot either gets corrected by a new submission or it doesn't, and there's no second, role-gated action on this screen.
- `occupied_beds`/`icu_beds_occupied` are **not** validated against `total_beds`/`icu_beds_total` - a facility genuinely running over its nominal capacity (overflow beds, hallway admissions) during a real outbreak is exactly the "can the system absorb this" signal this module exists to surface, not invalid data to reject. Same "don't clamp away a meaningful over-target signal" reasoning `VaccinationRecord.coverage_rate/1` already applied.
- `icu_occupancy_rate/1` returns `nil` when a facility has zero ICU beds, rather than a misleading `0.0` or a crash - a facility legitimately having no ICU capacity at all is a real state, not an edge case to paper over. The LiveView renders this as "No ICU beds" rather than a percentage.
- `capacity_status/1` (`:adequate`/`:near_capacity`/`:over_capacity` at 80%/100% bed occupancy) is driven by general bed occupancy only, not blended with ICU occupancy - stacking two independent tier systems into one first slice would be guessing at a combined-severity rule with no real use case behind it yet. Same honestly-flagged-arbitrary threshold spirit as `PredictiveAnalytics.RiskScore`'s tiers and `VaccinationRecord`'s coverage badge, not calibrated against a real target yet.
- Not wired into `PredictiveAnalytics.list_risk_scores/1` this slice, despite the facility-level grain making it a comparatively quick addition unlike Vaccination Monitoring's - still real, separate work (deciding how bed strain should combine with the existing case-trend tier isn't something to guess at without a real use case), and out of scope for this slice specifically. Logged here as the easier of the two still-open `PredictiveAnalytics` integrations.
- `time_ago/1` reused from the shared `ZamHealthWatchWeb.TimeHelpers` extracted in Iteration 7 - now a fourth consumer, no further duplication introduced.

**Built:**

- [x] Migration: `capacity_reports` table (`total_beds`, `occupied_beds`, `icu_beds_total`, `icu_beds_occupied`, `admissions_today`, `facility_id`, `reported_by_id`, indexed on `facility_id`/`reported_by_id`).
- [x] `HospitalCapacity` context + `CapacityReport` schema - `list_capacity_reports/0`, `get_capacity_report!/1`, `record_capacity/1`, `change_capacity_report/2`, `bed_occupancy_rate/1`, `icu_occupancy_rate/1`, `icu_beds_available/1`, `capacity_status/1`, PubSub broadcast (`"capacity_reports"` topic) on create.
- [x] `HospitalLive.Index` at `/hospitals` - a capacity-submission form above a live-updating table with a computed Adequate/Near capacity/Over capacity badge and an ICU free/total column (or "No ICU beds").
- [x] Tests: context tests (list, get, record with valid/invalid data - required fields, non-positive `total_beds`, negative counts, the deliberate over-capacity-not-rejected case, bad `facility_id`/`reported_by_id` FKs, broadcast; `bed_occupancy_rate/1` including not-capped-above-100%; `icu_occupancy_rate/1` including the zero-ICU-beds `nil` case; `icu_beds_available/1` including going negative; all three `capacity_status/1` tiers); LiveView tests (auth redirect, empty state, listing, recording with valid data, validation error, the server overriding a tampered `reported_by_id`, live broadcast to a second viewer, all three badge tiers, and the "No ICU beds" render).

**Status:** `mix test`-verified (362 tests, 0 failures) - clean first run, no fixes needed. Iteration 8 is closed, and with it all four of the brief's Construction modules (Laboratory Reporting, Vaccination Monitoring, Drug Availability, Hospital Capacity). Next: pick one of the deferred integration threads - `PredictiveAnalytics` district-level scoring (unblocks Vaccination Monitoring feeding risk scores), `PredictiveAnalytics` + Hospital Capacity (the easier of the two, same facility grain), or the Drug Availability shortage/active-outbreak correlation - or move toward Transition-phase polish (Public Alerts, Health Worker Portal, National Reporting, or deployment).

---

## Iteration 9 — Hospital Capacity → PredictiveAnalytics integration

**Goal:** wire the one deferred integration Iteration 8 flagged as "comparatively easy" - surface each facility's latest hospital capacity status alongside its existing case-trend risk tier on `/risk`, since `HospitalCapacity` and `PredictiveAnalytics.list_risk_scores/1` already share the same facility grain (unlike `VaccinationMonitoring`'s still-open district/facility mismatch, which stays deferred).

**Decisions:**

- Purely additive, not blended: `RiskScore` gains a new `capacity_status` field shown in its own "Hospital capacity" column next to the existing `tier` badge, not folded into `tier` itself or a new combined score. Deciding how bed strain should weigh against a case-count trend is a real judgment call with no real use case behind it yet - the same reasoning `HospitalCapacity`'s own moduledoc already gave for not guessing at this in Iteration 8. Showing both signals side by side is what actually answers the brief's "one connected signal rather than four separate ones" framing at this stage, without inventing a formula.
- `HospitalCapacity.latest_capacity_by_facility/0` is the new primitive that makes this possible - a Postgres `DISTINCT ON` query returning `%{facility_id => CapacityReport}` for whichever report is most recently reported per facility. Built as a general-purpose lookup, not a `PredictiveAnalytics`-only helper, so anywhere else "what's this facility's current capacity" comes up later can reuse it.
- The dependency still runs one direction only: `PredictiveAnalytics` now depends on `HospitalCapacity`'s public API, but `HospitalCapacity` stays completely unaware `PredictiveAnalytics` exists - same decoupling every context in this project already keeps.
- `capacity_status_for/1` maps a `nil` lookup result (no capacity report ever submitted for a facility) to a new `:no_data` value, distinct from any of `CapacityReport.capacity_status/1`'s own three values - same "absence isn't a guessed default" call `latest_capacity_by_facility/0` already makes at the query layer.
- `RiskLive.Index`'s capacity badge reads "No reports yet" rather than reusing `tier_label(:insufficient_data)`'s "No data" text, even though both mean "nothing to go on yet" - the two badges sit in adjacent columns on the same row and mean different things (no case history vs. no capacity submission); sharing the exact wording risked reading as one signal instead of two independent ones.
- `RiskLive.Index` now subscribes to both `"cases"` and `"capacity_reports"` and recomputes every risk score on any event from either topic - same "recompute everything, don't hand-roll incremental tracking" call already made for this LiveView's case-only version, `EpidemiologyLive.Index`, and `MapLive.Index`. The existing `handle_info` clauses were changed from an unqualified `_case` variable to explicit `%Case{}`/`%CapacityReport{}` struct matches, since an unqualified variable name would have silently also matched the new capacity broadcasts - not a bug (both event types trigger the same recompute), but explicit matching makes it obvious at a glance which topic's broadcast triggered any given call.
- No migration - this is a pure code-level integration over data both contexts already persist.

**Built:**

- [x] `HospitalCapacity.latest_capacity_by_facility/0` - `%{facility_id => CapacityReport}` via `DISTINCT ON (facility_id)`, ordered by `inserted_at` descending.
- [x] `RiskScore.capacity_status` field and type (`:no_data | :adequate | :near_capacity | :over_capacity`).
- [x] `PredictiveAnalytics.list_risk_scores/1` now looks up and attaches each facility's `capacity_status` via a new private `capacity_status_for/1`.
- [x] `RiskLive.Index` - new "Hospital capacity" column with a status badge; subscribes to `"capacity_reports"` alongside `"cases"`; `handle_info` clauses changed to match on `%Case{}`/`%CapacityReport{}` explicitly.
- [x] Tests: `PredictiveAnalyticsTest` (`:no_data` for a facility with no capacity report; a report's status surfacing correctly via `CapacityReport.capacity_status/1`; only the latest of multiple reports for a facility counts); `RiskLive.IndexTest` (badge rendering for both no-data and a real status, live update on a new capacity report reported elsewhere).

**Status:** never explicitly closed at the time, but verified by every full-suite run since - its tests have passed in each one through Iteration 13's 482 tests, 0 failures. Closed.

---

## Iteration 10 — Real SMS delivery: Africa's Talking + a public alert subscriber list

**Goal:** close the two real, previously-flagged SMS/USSD gaps this project chose to tackle first (of the two identified when picking this iteration - see below for the other, still-deferred one): swap `PublicAlerts.AlertWorker`'s `Logger`-only mock delivery for real Africa's Talking SMS, and give `SmsReporting`'s reporter a reply (success or rejection reason) instead of silence - both of which needed an actual subscriber list and a real outbound-SMS mechanism to exist first, neither of which this project had before this iteration.

**Decisions:**

- A new `SmsGateway` context/behaviour (`send_sms/2`) is the shared "send this SMS" responsibility - genuinely its own thing now that two independent contexts (`PublicAlerts`, `SmsReporting`) need outbound SMS, neither of which should own a specific provider's HTTP details. Two implementations: `SmsGateway.Logger` (logs instead of sending - the default everywhere except a production boot with real credentials, and the only one ever exercised in `:test`) and `SmsGateway.AfricasTalking` (a real `Req` call). Selected via a plain `Application.get_env/3` module swap, not a mocking library - this project hasn't reached for one anywhere else, and a config-swapped module is enough for the one axis that actually varies.
- `SmsGateway.AfricasTalking`'s endpoint/method/request shape (`POST https://api.africastalking.com/version1/messaging`, form body `username`/`to`/`message`/optional `from`, `apiKey` header) was checked against Africa's Talking's own published API reference this session, not guessed at. Its exact successful-response JSON shape and status code were **not** independently confirmed (the live docs page is JS-rendered and this session's web tools couldn't render it) - `handle_response/1` deliberately accepts any `2xx` status alongside the expected body shape rather than pinning a single guessed-at code, and this is flagged in the module's own moduledoc as the first place to check if a real send behaves unexpectedly. Same "flag what wasn't checked live" discipline this project already applies to Nx/Broadway/Oban.
- Tested against a `Req.Test` stub (`config :zamhealthwatch, :sms_gateway_req_options`, merged into every real request's options, empty everywhere except `:test`) rather than a real network call or a mocking library - `Req.Test` ships with `Req` itself (already a dependency), the documented, dependency-free way to test a `Req`-based client.
- A missing Africa's Talking API key in production does **not** `raise` at boot the way missing `DATABASE_URL`/`SECRET_KEY_BASE` already do - it falls back to `SmsGateway.Logger` with a loud startup warning instead. Real, deliberate asymmetry: SMS delivery is a real but non-essential feature of this app, unlike its database connection: a degraded (log-only) alerting path is a better failure mode than refusing to start entirely.
- A new `alert_subscribers` table/`PublicAlerts.AlertSubscriber` schema (just `phone` + when subscribed, no lifecycle - same "no rule guessed at without a real use case" call every other single-purpose schema in this project already makes) backs the subscriber list `AlertWorker` broadcasts to. Named `AlertSubscriber`, not `Subscriber` - `PublicAlerts.Subscriber` was already taken by the pre-existing `GenServer` that reacts to newly reported cases, a genuinely different thing (a process, not a phone number); reusing the bare name for both would have been exactly the ambiguity this project's naming has avoided everywhere else.
- `PublicAlerts` gains its first top-level context file this iteration (`subscribe/1`, `unsubscribe/1`, `list_subscriber_phones/0`, `handle_inbound_sms/2`) - before now "Public Alerts" was only `AlertWorker` and `Subscriber`, with nothing answering "who receives an alert" at all.
- Opt-in/opt-out is a fixed SMS keyword grammar (`SUBSCRIBE`/`STOP`, case-insensitive, whitespace-tolerant) - same "smallest possible grammar, no NLP risk" call `SmsReporting.report_from_sms/2`'s own `REPORT <DISEASE> <FACILITY_CODE>` grammar already made, for the same reason. Routed from `SmsWebhookController` itself, *before* falling through to `SmsReporting.Pipeline.push/2`, rather than threaded through `SmsReporting`'s Broadway pipeline - a single-row subscribe/unsubscribe write is a fundamentally smaller, synchronous operation than parsing and creating a `Case`, and doesn't need Broadway's demand-driven backpressure to justify the extra moving parts. Deciding "is this a keyword or a report" is exactly the controller's own job (GRASP *Controller*), not something to push onto `SmsReporting`, which has no reason to know `PublicAlerts` exists.
- `AlertWorker` stays one Oban job per **case** (not per recipient), looping over every subscriber inline - simpler than a job-per-recipient fan-out, but a real, logged trade-off: a retried job (e.g. after a systemic outage) re-sends to every subscriber, including any who may have already received it on an earlier partial attempt, since there's no per-recipient delivery record to dedupe against yet. The job is only considered failed (triggering Oban's retry) when **every** send failed and there was at least one to send to - the shape a real provider outage would take; a handful of individual failures (e.g. one bad number) among otherwise-successful sends are logged and left undelivered rather than retried, since retrying the whole job over one bad number would re-send to everyone who already got it.
- `SmsReporting.confirmation_message/1` (Information Expert - `SmsReporting` already knows what every `report_from_sms/2` result means) turns that result into reply text; `SmsReporting.Pipeline.handle_message/3` sends it via `SmsGateway.send_sms/2`, since that's the one place that already has both the outcome and the reporter's `from` number.
- Of the two real SMS/USSD gaps identified when choosing this iteration over the alternative, this one (real delivery, both directions) was picked as the smaller, more contained slice; the other - a USSD guided, stateful, multi-step menu session (structurally different from SMS's one-shot text, and still nonexistent in this project) - remains open, logged here rather than half-built.

**Built:**

- [x] Migration: `alert_subscribers` table (`phone`, unique index).
- [x] `SmsGateway` behaviour + dispatcher; `SmsGateway.Logger` (mock, default); `SmsGateway.AfricasTalking` (real `Req`-based delivery).
- [x] `PublicAlerts` context (new top-level file) + `PublicAlerts.AlertSubscriber` schema - `subscribe/1`, `unsubscribe/1`, `list_subscriber_phones/0`, `handle_inbound_sms/2`.
- [x] `SmsWebhookController` - routes `SUBSCRIBE`/`STOP` to `PublicAlerts.handle_inbound_sms/2` before falling through to `SmsReporting.Pipeline.push/2`.
- [x] `AlertWorker` - real delivery to every subscriber via `SmsGateway`, partial- vs. total-failure handling as described above.
- [x] `SmsReporting.confirmation_message/1`; `SmsReporting.Pipeline.handle_message/3` now sends it as a reply via `SmsGateway`.
- [x] `config/config.exs`/`config/runtime.exs`/`config/test.exs` wiring for `:sms_gateway` and the `Req.Test` stub option.
- [x] Tests: `SmsGateway.Logger` (logs and returns `:ok`); `SmsGateway.send_sms/2` dispatch; `SmsGateway.AfricasTalking` against a `Req.Test` stub (success, a rejected recipient, a non-2xx response, missing config raising); `PublicAlerts` context (`subscribe/1` including idempotency, `unsubscribe/1` including the no-op case, `list_subscriber_phones/0`, `handle_inbound_sms/2` for both keywords and a non-keyword); `AlertWorker` (multiple subscribers, zero subscribers, the case-missing raise, the all-deliveries-failed retry path via a small hand-written failing `SmsGateway`); `SmsReporting.confirmation_message/1` (every branch); the Broadway pipeline tests extended to assert the reply landed too; `SmsWebhookController` extended with `SUBSCRIBE`/`STOP` routing tests.

**Status:** `mix test`-verified (393 tests, 0 failures) - clean first run, no fixes needed. Iteration 10 is closed. Next: the USSD guided menu flow deferred above, or Health Worker Portal / National Reporting (the two brief modules still unbuilt from scratch).

---

## Iteration 10 — Live verification + a phone-normalization fix

**Goal:** `mix test` passing (Iteration 10's own close-out) only proves the code's logic is internally consistent - it doesn't prove `/webhooks/sms` actually works end to end against a real running server and a real Postgres connection, since `SmsGateway.Logger` is the only implementation ever exercised in `:test`. This slice is that live verification, plus the one real finding it surfaced.

**Decisions:**

- Manually exercised the full SUBSCRIBE → report-with-alert → STOP → report-with-fewer-subscribers → rejected-report path via `curl.exe` against a locally running `mix phx.server`, reading the actual Bandit/Ecto/Oban console log output rather than trusting the test suite alone. Every step matched what the code predicts, with one exception below.
- That exception: a stray `alert_subscribers` row with a leading-space phone number (`" 260971111111"` instead of `"+260971111111"`) caused `AlertWorker` to report "notifying 2 subscriber(s)" instead of 1, and to deliver to a malformed number nothing could ever `STOP`. Root cause: `application/x-www-form-urlencoded` decodes a literal `+` as a space, so an earlier manual test that POSTed an un-percent-encoded `+` created this row - `unique_constraint(:phone)` had no way to catch it, since `" 260..."` and `"+260..."` are different strings, and `unsubscribe/1`'s exact-match delete could never reach it either.
- Fixed by trimming `phone` in `AlertSubscriber.changeset/2` (`update_change(:phone, &String.trim/1)`, before `validate_required/2` so an all-whitespace value still correctly fails rather than silently becoming `""`). Deliberately a defensive minimum, not full phone-number normalization - no E.164 validation/formatting was added, since a real Africa's Talking webhook sends a clean MSISDN and this fix targets the one specific failure mode actually observed, not every theoretical malformed-input shape.
- The stray row itself was cleaned up directly in the dev database (`DELETE FROM alert_subscribers WHERE phone !~ '^\+'`), not through application code - it was bad data from manual testing, not something any user-facing flow needs to recover from automatically.
- The `mix test` re-run this trim fix's own new test immediately caught a second, real bug: `PublicAlerts.subscribe/1`'s duplicate-recovery path (what runs when `Repo.insert/1` hits the `unique_constraint(:phone)` conflict) re-queried using the raw, untrimmed `phone` function argument rather than the trimmed value the changeset actually inserted/conflicted on - `Repo.get_by!(AlertSubscriber, phone: phone)` against `" +260971234567"` found nothing, since only `"+260971234567"` exists, and raised `Ecto.NoResultsError` instead of returning the existing row. Fixed by reading the phone back out of the changeset (`Ecto.Changeset.get_field(changeset, :phone)`) instead of the function argument. A clean example of why the new test was worth writing even though it looked like it was only testing the schema-level trim - it exercised `subscribe/1`'s full conflict-recovery path too, not just `AlertSubscriber.changeset/2` in isolation. Separately, `config/test.exs` had drifted from `config/dev.exs`'s DB password (`"Lacas24."` vs. the real local Postgres password, `"postgres"`) - not a code bug, but it blocked this verification until caught and fixed too.

**Built:**

- [x] `AlertSubscriber.changeset/2` - trims `phone` before validation.
- [x] `PublicAlerts.subscribe/1` - duplicate-recovery lookup now uses the trimmed phone from the changeset, not the raw argument.
- [x] Tests: `PublicAlertsTest` - `subscribe/1` trims surrounding whitespace; a whitespace-padded duplicate collapses into the existing subscription instead of creating a second row (this second assertion is what caught the `subscribe/1` bug above).
- [x] `config/test.exs`'s DB password corrected to match `config/dev.exs` and the real local Postgres instance.

**Status:** Live-verified against a real `mix phx.server` + Postgres run first; that surfaced the phone-trim fix. The `subscribe/1` duplicate-recovery bug was then caught by this slice's own new test on the next `mix test` run (395 tests, 1 failure). Re-run confirmed green after the fix. Closed.

---

## Iteration 11 — USSD guided menu flow

**Goal:** close the second, previously-deferred SMS/USSD gap (Iteration 10's own entry named it explicitly): a stateful, multi-step USSD session (`*384#`-style) distinct from the one-shot SMS `REPORT <DISEASE> <FACILITY_CODE>` grammar and `SUBSCRIBE`/`STOP` keywords - structurally different because a USSD gateway holds a session open across several request/response round-trips with the same phone number, not one inbound message handled and forgotten.

**Decisions:**

- No session state is persisted anywhere - no `GenServer`, ETS table, or database-backed session row. Africa's Talking's USSD protocol sends the *entire* accumulated input history in `text` on every request within a session (e.g. `"1*2*UTH"` on the third round-trip of a report), not just the latest keypress - so the whole menu state is reconstructible by parsing `text` fresh on every request. `UssdReporting.handle_session/2` is a pure function of `(phone, text)`, nothing else - no "where is this phone number in its session" mutable state to track anywhere, and no real use case yet for anything a session row would add (e.g. resuming an abandoned session). Same "no lifecycle without a real use case" call every other single-purpose piece of this project already makes.
- Reuses `SmsReporting.report_from_sms/2` + `confirmation_message/1` and `PublicAlerts.subscribe/1`/`unsubscribe/1` rather than duplicating either context's logic - `UssdReporting`'s only real job is translating numeric menu choices into the same inputs those contexts already validate (a disease token, a facility code, a bare subscribe/unsubscribe). Information Expert again: neither `SmsReporting` nor `PublicAlerts` needs to know a USSD menu exists.
- New `UssdWebhookController`/`POST /webhooks/ussd`, separate from `SmsWebhookController` - different inbound payload shape (`sessionId`/`serviceCode`/`phoneNumber`/`text` vs. `from`/`text`) and a genuinely different response contract: USSD requires a `text/plain` body prefixed `CON ` (keep the session open) or `END ` (final message), not a bare `200`. `UssdReporting.handle_session/2` returns plain `{:continue, text}` / `{:end, text}` tuples and stays ignorant of that wire format entirely - same controller/context split `SmsWebhookController` already keeps from `PublicAlerts`/`SmsReporting`.
- Menu: option 1 (report) prompts for a disease (fixed 1-5 menu matching `SmsReporting`'s five recognized diseases) then a typed facility code, reusing the same `REPORT <DISEASE> <CODE>` command string `SmsReporting.report_from_sms/2` already parses rather than inventing a second disease/facility validation path; option 2 subscribes the sender; option 3 unsubscribes. Any unrecognized input at any step - an out-of-range menu digit, extra trailing input after a complete path, anything else - ends the session with a generic "Invalid selection" message rather than silently continuing or crashing.
- No migration - this context holds no new state of its own; everything it touches already exists (`cases`, `alert_subscribers`, `users`).

**Built:**

- [x] `UssdReporting` context - `handle_session/2`, stateless menu routing over `SmsReporting`/`PublicAlerts`.
- [x] `UssdWebhookController` - `POST /webhooks/ussd`, `CON `/`END `-prefixed `text/plain` responses.
- [x] Router: `/webhooks/ussd` added alongside the existing `/webhooks/sms`.
- [x] Tests: `UssdReportingTest` (main menu, disease menu, facility prompt, a real case created end-to-end, unknown facility code reusing `SmsReporting`'s own rejection reply, trailing extra input rejected, subscribe/unsubscribe including idempotency and the never-subscribed no-op); `UssdWebhookControllerTest` (empty-text session start, a full report path creating a real case, subscribe via option 2, a malformed payload still responding 200 with an `END` message).

**Status:** 411 tests, 0 failures. Closed.

---

## Iteration 12 — Health Worker Portal (slice 1 of 4)

**Goal:** the first of three Health Worker Portal sub-slices. Re-reading the brief's own stated scope for this module ("login, case entry, treatment guidance, local case tracking") against what already existed by Iteration 11 found that login (Accounts/`phx.gen.auth`) and case entry (`CaseLive.Index`, Iteration 1) were already built - this module wasn't a ground-up build, it was closing the two genuinely missing pieces: treatment guidance content, and a facility-scoped "my work" landing page (slice 2). This first slice is the guidance content.

**Decisions:**

- `Guidance` is a static, non-database-backed context - a fixed Elixir map (`@guidance`), keyed by the same disease atoms `Case.disease_options/0` already defines, not a new schema/migration. Same "no lifecycle without a real use case" call this project has made repeatedly (`AlertSubscriber`, `DrugStock`, `CapacityReport`, `VaccinationRecord`) - nothing here needs editing, versioning, or per-user state yet.
- Content is case-definition/immediate-action/when-to-refer/reporting guidance only - deliberately **no specific drug names or dosages**. A wrong or outdated hardcoded dose is an active safety risk this project has no mechanism to keep current; guidance instead points to "national treatment guidelines" for dosing specifics. Same "don't guess at something that could be actively wrong" judgment call already made elsewhere (e.g. Africa's Talking's exact USSD response shape in Iteration 11).
- `GuidanceLive.Index.safe_to_disease/2` never calls `String.to_atom/1`/`String.to_existing_atom/1` on the raw `disease` URL param - it matches the param string against the already-atomized `diseases` list (`Enum.find(diseases, &(Atom.to_string(&1) == disease_param))`). An unrecognized param simply matches nothing rather than growing the atom table on untrusted input.
- Routed at `/guidance` and `/guidance/:disease`, both inside the existing `:require_authenticated_user` live_session - guidance is useful to any authenticated role, not gated further.

**Built:**

- [x] `Guidance` context - `list_diseases/0`, `get/1`, static content for cholera/malaria/typhoid/covid19/measles.
- [x] `GuidanceLive.Index` - disease picker, safe URL-param-to-atom matching.
- [x] Router: `/guidance`, `/guidance/:disease`.
- [x] Tests: `GuidanceTest`, `GuidanceLive.IndexTest`.

**Status:** passing alongside the rest of the suite. Closed.

---

## Iteration 12 — Health Worker Portal (slice 2 of 4)

**Goal:** the second sub-slice - a facility-scoped landing page (`PortalLive.Index`, `/portal`) giving a health worker "my work" at a glance: their facility's recent cases, recent drug stock, and current capacity status, plus shortcuts into the existing report screens. This is what actually needed new facility-filtered queries; `CaseManagement.list_cases_by_facility/1` existed since Iteration 0 but had no real caller until now.

**Decisions:**

- Scoped entirely by `current_scope.user.facility_id` - a health worker with no facility assigned yet sees an empty state pointing at `/admin/users` ("Manage users") rather than silently falling back to showing every facility's data. This empty-state pattern (a distinct message, not a default to "show everything") is what Slice 3 later reuses for the point-of-care screens themselves.
- `CaseManagement.list_cases_by_facility/1` (pre-existing, newly given a real caller) and the newly added `DrugAvailability.list_drug_stocks_by_facility/1` both order by `inserted_at desc` and are capped to the 5 most recent via a private `recent/1` helper - a dashboard, not a full list, so "most recent N" is the page's own concern, not the context's.
- `HospitalCapacity.latest_capacity_by_facility/0` (built in Iteration 9 for `PredictiveAnalytics`) is reused unmodified for the capacity-status badge - the "latest report per facility" shape it already returns is exactly what a landing page needs, no new query required.
- `handle_info/2` only recomputes (`maybe_refresh/2`) when a broadcast event's own `facility_id` matches the viewer's - deliberately different from `EpidemiologyLive.Index`/`RiskLive.Index`, which recompute on *every* event because they aggregate cross-facility by design. A single-facility dashboard has no reason to react to another facility's activity.
- `fetch_facility/1` rescues `Ecto.NoResultsError` the same way `AlertWorker.facility_name/1` already does - a user's `facility_id` isn't a real FK constraint on `users` (Iteration 0's decision), so a since-deleted facility shouldn't crash this page.

**Built:**

- [x] `CaseManagement.list_cases_by_facility/1` - now ordered (`desc: inserted_at`), previously unordered with no real caller.
- [x] `DrugAvailability.list_drug_stocks_by_facility/1` - same facility-filtered/newest-first shape.
- [x] `PortalLive.Index` - `/portal`, facility-scoped recent cases/stock/capacity, PubSub-filtered live updates.
- [x] Router: `/portal`.
- [x] Tests: `CaseManagementTest`/`DrugAvailabilityTest` ordering tests (with the established inserted_at-backdating fix for same-second insert flakiness); `PortalLive.IndexTest` (logged-out redirect, unassigned empty state, assigned empty state, cross-facility isolation, live PubSub scoping).

**Status:** passing alongside the rest of the suite. Closed.

---

## Iteration 12 — Health Worker Portal (slice 3 of 3)

**Goal:** the third sub-slice - facility-scope the five existing point-of-care screens (`CaseLive.Index`, `LabLive.Index`, `VaccinationLive.Index`, `DrugLive.Index`, `HospitalLive.Index`) themselves for the `health_worker` role, so a health worker's day-to-day reporting screens show and accept data for their own facility only, not every facility in the system. `Map`/`EpidemiologyLive.Index`/`RiskLive.Index` are deliberately left cross-facility for everyone - those are oversight/aggregate views, not a single worker's own work.

**Decisions:**

- Scoping applies to the `health_worker` role only - `district_officer`/`moh_admin` (and a `nil`-role user) remain unrestricted on these same five screens, matching the brief's own district/MOH-level oversight responsibilities. A `facility_scope/1` helper (`:unrestricted` / `:unassigned` / `{:locked, facility_id}`) is duplicated with a cross-referencing comment across all five LiveViews rather than extracted into a shared module - same small-per-module-helper convention `with_reporter/2` already established project-wide, now five times instead of four.
- An unassigned `health_worker` (`facility_id: nil`) sees the same "get assigned" message `PortalLive.Index` already shows, with the report form itself hidden entirely - not a fallback to unscoped visibility. There is nothing meaningful to scope *to* yet, so showing an empty list with no explanation would be worse than being explicit about why.
- The case-report form is genuinely **locked**, not just filtered: an assigned health worker's `facility_id` is forced server-side on every submission (`apply_scope/2`, same server-side-enforcement precedent `with_reporter/2` already set for `reported_by_id`) regardless of what the client sends, and the facility `<select>` is replaced in the UI with a disabled, pre-filled display of their own facility's name. Same treatment applied to `DrugLive.Index`'s and `HospitalLive.Index`'s own `facility_id` fields, for the same reason - a health worker choosing "report for a different facility" from a dropdown would otherwise have been possible even though the list view hid that facility's data from them.
- **Schema-grain mismatch, resolved per screen:**
  - `LabTest` has no `facility_id` of its own - only `case_id`, linking to `CaseManagement.Case` (which does carry `facility_id`). Rather than a SQL join (which would mean `LabReporting` reaching directly into `CaseManagement.Case`'s schema - the cross-context decoupling this project keeps everywhere else), `LabReporting.list_lab_tests_by_facility/1` asks `CaseManagement` which case ids belong to the facility first, then filters lab tests by that id set in a second query. There's no `facility_id` field on the lab-test-request form to lock the way the others are locked - instead, the `case_id` dropdown is pre-filtered to the worker's own facility in `mount/3`, **and** `handle_event("save", ...)` independently re-checks the submitted case's actual `facility_id` server-side (`check_scope/2`) before calling `LabReporting.request_test/1`, the same "don't trust the dropdown being filtered" precedent every role-gated button in this project already follows.
  - `VaccinationRecord` is genuinely **district**-grain, not facility-grain - it has a `district_id` column and no `facility_id` at all (a deliberate earlier scoping decision, not an oversight). A health worker only has a `facility_id`, so `VaccinationLive.Index` narrows its scope one step further via `district_scope/1`: `{:locked, facility_id}` → `{:locked, facility.district_id}`. This means a health worker sees and reports into their *whole district's* coverage records, not only records somehow tied to their own facility specifically - there is no finer-grained link on this schema to narrow it further. Logged here as a known, deliberate broadening, not a bug. `Geography.Facility.district_id` is itself optional (no facility-management UI yet to guarantee it's set), so a worker whose own facility has no district on record gets a third, distinct `:no_district` state with its own explanatory message, rather than silently matching `:unassigned`'s wording or falling back to showing everything.
- `HospitalCapacity.list_capacity_reports_by_facility/1` is new - `latest_capacity_by_facility/0` (Iteration 9) only ever returns the single latest report per facility, which is right for `PortalLive.Index`'s dashboard badge but wrong for `HospitalLive.Index`'s own table, which needs every report at the facility, same "facility-filtered, newest-first" shape `CaseManagement`/`DrugAvailability` already have.

**Built:**

- [x] `LabReporting.list_lab_tests_by_facility/1` - two-query, decoupled facility scoping via `CaseManagement`.
- [x] `VaccinationMonitoring.list_vaccination_records_by_district/1` - district-grain scoping.
- [x] `HospitalCapacity.list_capacity_reports_by_facility/1` - full per-facility report list, distinct from the existing latest-only lookup.
- [x] `CaseLive.Index`/`DrugLive.Index`/`HospitalLive.Index` - facility_scope/1, locked facility_id forms, scoped list queries.
- [x] `LabLive.Index` - facility-scoped case dropdown and lab-test list, server-side case-facility re-check on submit.
- [x] `VaccinationLive.Index` - district_scope/1 (facility → district), locked district_id form, a distinct `:no_district` state.
- [x] Tests: new facility-scoping `describe` blocks across all five `*LiveTest` modules (unassigned empty state, cross-facility list isolation, locked form field, forged-param rejection/override, unrestricted roles unaffected); new context tests for the three new query functions.

**Status:** 456 tests, 0 failures. Closed.

Two real issues surfaced and were fixed during verification, both worth logging:

- Two ordering tests (`CaseManagementTest.list_cases_by_facility/1`, `DrugAvailabilityTest.list_drug_stocks_by_facility/1`) backdated an `older` fixture's `inserted_at` via `Repo.update!/1` but never reassigned the local `older` variable to the update's return value - the subsequent `==` assertion compared the DB's correctly-backdated row against a stale, pre-update struct still held in `older`. Fixed by reassigning (`older = older |> Ecto.Changeset.change(...) |> Repo.update!()`); the `list_cases_by_facility/1` instance of this bug predates this slice.
- Three of this slice's own new isolation tests (`CaseLive`/`DrugLive`/`VaccinationLive`) initially asserted on the *absence* of a disease/medicine/antigen name to prove another facility's/district's record wasn't shown - but those fields are closed enums, and their `<select>` always lists every possible value as a choice for a *new* report regardless of what's in the scoped list below it, so the assertion never actually exercised the scoping. Fixed by asserting on the rendered "N reported so far" count (which does reflect the scoped query) and the other facility's/district's own name instead.
- Four pre-existing tests (two in `CaseLive.IndexTest`, two in `LabLive.IndexTest`) used a bare `user_fixture() |> set_role(:health_worker)` with no facility purely as a stand-in for "a user with some role," to test the Confirm/Resolve and lab-result buttons - unrelated to facility scoping. Under this slice's new rule, a facility-less health worker is `:unassigned` and sees an empty list, so there was nothing to click. Fixed by assigning each of those test users to the same facility as the case/lab test under test.

Also fixed an unrelated ElixirLS warning caught along the way: the new `handle_event("save", ...)` clause had been inserted between `LabLive.Index`'s two `handle_event/3` clauses rather than next to the other one - cosmetic (clause dispatch doesn't care about grouping), but moved `check_scope/2` below both clauses to keep the convention this project follows elsewhere.

---

## Iteration 13 — National Reporting

**Goal:** the twelfth and last of the brief's modules - "aggregated, exportable reporting for MOH-level consumption - the rollup of everything else." Unlike every other module, this one started with no new domain data of its own to model - every other context's public API already existed by the time this iteration started, so the entire job was deciding how to shape what they already return into one MOH-facing snapshot, not what to persist.

**Decisions (scope, confirmed with the project owner before writing code):**

- **CSV only**, not PDF/Excel - the brief says "exportable," not which format, and a CSV is what a MOH analyst actually pastes straight into Excel/Stata/R. Written as a minimal hand-rolled RFC 4180 writer (quote-on-comma/quote/newline, `\r\n` line endings) rather than pulling in a dependency like NimbleCSV for what turned out to be a dozen lines of code.
- **A current snapshot, not a selectable date range** - no module in this project exposes an as-of/historical query yet (`PredictiveAnalytics`'s weekly trend buckets aside, and those aren't a general date-range primitive), so a date-range selector would have been a UI control with nothing underneath it to actually filter by historically. Logged as the natural next slice once a module exists that needs one.
- **Facility-level rollup, one row per facility, not one row per case/test/record** - "aggregated" is the brief's own word, and a row per individual entry is what the Epidemiology Dashboard and each module's own screen already give a closer look at. Vaccination coverage is genuinely district-grain (`VaccinationRecord` has no `facility_id` at all - see Iteration 8's own decision log), so it stays a second, separate table in the same CSV rather than being broadcast onto every facility row in that district, which would overstate a precision the data doesn't have.
- **`moh_admin`-only**, both the on-screen preview and the CSV download - matches the brief's own "MOH-level consumption" framing and the existing `:require_moh_admin` gate `/admin/users` already uses. The CSV download is a plain controller action, not a LiveView route - a browser "Save As" download needs a real HTTP response with a `content-disposition` header, which a LiveView socket can't produce without an extra JS-hook workaround this project had no other reason to build. `UserAuth.require_moh_admin/2` is a new controller-pipeline plug added alongside the existing `on_mount(:require_moh_admin, ...)`, composed on `require_authenticated_user/2` the same way the on_mount version composes on `on_mount(:require_authenticated, ...)`.

**Built:**

- [x] `NationalReporting` context - `facility_summary/1` (one `FacilitySummary` struct per facility, folding in case counts by status, lab test counts by status, drug stock/shortage counts, and the existing `PredictiveAnalytics.list_risk_scores/1` read for risk tier + hospital capacity status), `vaccination_coverage/0` (records paired with district names), and `export_csv/1` (both tables as CSV iodata). Depends on every other context's existing public API only - no new cross-context coupling in the other direction.
- [x] `NationalReporting.FacilitySummary` - a computed, non-persisted struct, same "no schema/changeset/migration for a read-only shape" convention `PredictiveAnalytics.RiskScore` already set.
- [x] `NationalReportingController` - `GET /reports/national.csv`, gated by the new `UserAuth.require_moh_admin/2` plug.
- [x] `NationalReportingLive.Index` - `/reports/national`, inside the existing `:require_moh_admin` live_session alongside `/admin/users`; renders both tables and links to the CSV download; subscribes to all five contributing contexts' PubSub topics and recomputes the whole snapshot on any of their events, same "recompute everything" call `EpidemiologyLive.Index`/`MapLive.Index`/`RiskLive.Index` already make.
- [x] Tests: `NationalReportingTest` (facility summary folding, vaccination pairing, CSV structure and comma-quoting), `NationalReportingControllerTest` (auth/role gating, CSV response headers and body), `NationalReportingLive.IndexTest` (auth/role gating, empty states, rendered rollup, live recompute on a new case).

**Status:** 482 tests, 0 failures. Closed. With this, all twelve of the brief's modules have a working first slice.

One issue surfaced and was fixed during verification: the `export_csv/1` row test expected a facility with one just-reported case to read as `Insufficient data`, but that tier only applies to a facility with zero cases across all four weekly buckets. One case this week gives counts of `[0, 0, 0, 1]` - a least-squares slope of 0.3, below the 0.5 "elevated" threshold - so the correct tier is `Stable`. The test's expectation was wrong, not the code; fixed by asserting the real row (`...,No data,Stable,0.3`).

---

## Iteration 14 — Deployment (Transition)

**Goal:** the brief's Transition phase - "a hosted, working instance a recruiter or collaborator can actually click through." Getting there meant more than writing a Dockerfile. Before this iteration, nobody could log in to a deployed copy, there was no navigation between screens, the home page and header were still the Phoenix generator's, and an empty database would have demoed nothing.

**Decisions (hosting and login confirmed with the project owner before writing code):**

- **Render (free web service, Docker) + Neon (free Postgres).** Researched current pricing first. Fly.io no longer has a free tier, and its managed Postgres starts at about $38/month. Render's own free Postgres is deleted 30 days after creation. Gigalixir's free database is capped at 10,000 rows and 2 connections, which is tight once Oban is using it. Neon's free plan doesn't expire and needs no card. The trade-off accepted: Render's free instance sleeps after 15 idle minutes and takes about a minute to wake. Both are in Frankfurt, the closest region to Zambia either offers. PostGIS turned out not to be needed in production: facility coordinates are plain float columns, so any vanilla Postgres works.
- **Demo accounts instead of email.** Login is magic-link by default, and the deployed app has no mail provider. Rather than adding one (which needs an API key and usually a verified domain), `ZamHealthWatch.Demo` seeds one password-login account per role (health worker at Kabwata Clinic, district officer, MOH admin), and the home page publishes the credentials. They're meant to be shared, so they're in source control in plain text. Every visitor uses the same logins, so one of them can change a demo password or, as MOH admin, a role. `ensure_accounts!/0` resets all three on every boot to undo that, and the free plan's idle restarts make those boots frequent.
- **Logger mailer in production.** `config.exs` sets `Swoosh.Adapters.Local`, but `prod.exs` turns off its in-memory storage, so the first magic-link request on a deployed copy would have crashed. Production now uses `Swoosh.Adapters.Logger`, which writes emails to the server log. The login page tells visitors to use the password form instead, and the service owner can still sign in with their own address by copying the link out of Render's logs.
- **Demo activity, seeded once.** `Demo.seed_activity!/1` runs only on a database with zero cases, so it never mixes into real data or duplicates itself. It goes through each context's public API, so broadcasts and lab-result side effects behave exactly as in normal use. Cases are backdated so `/risk` has a real shape: Kabwata Clinic's cholera rises 1 → 2 → 3 → 5 a week (Elevated), UTH is a steady 2 a week (Stable), and Monze's only case falls outside the window (No data). Known limitation: the trend is relative to when the database was seeded, so after four weeks these cases age out of the risk window. Re-basing demo timestamps on boot is a possible follow-up.
- **Migrate and seed on every boot**, via `ZamHealthWatch.Release.setup/0` in the container's start command. Render's free plan has no pre-deploy command and no shell, and both steps are idempotent. Seeding starts the whole application rather than only the Repo, because the contexts broadcast over PubSub; the HTTP port stays closed until the final `start`.
- **Neon TLS configured explicitly** in `runtime.exs` behind `DATABASE_SSL`, with full certificate and hostname verification plus SNI, which Neon uses to route connections. Neon's libpq-style `?sslmode=require` query string is stripped, since Ecto would otherwise treat those parameters as unknown Repo options. The `DATABASE_URL` must be Neon's direct endpoint, not the pooled one: Oban uses `LISTEN/NOTIFY`, which PgBouncer's transaction pooling breaks.
- **`/health`** for Render's health checks. It's routed outside the browser pipeline, excluded from `force_ssl` (checks arrive over plain HTTP), and deliberately doesn't touch the database, since a check every few seconds would keep Neon's compute from ever suspending.
- **A real header and home page.** The navigation lists every screen once a user is logged in, adding National Reporting and user management for MOH admins only. The home page explains what the project is, says plainly that it's a prototype on demo data, and lists the demo logins.

**Built:**

- [x] `Dockerfile` (two-stage release build on `elixir:1.19.6-otp-28-slim`), `.dockerignore`, `render.yaml` Blueprint.
- [x] `ZamHealthWatch.Release` - `setup/0`, `migrate/0`, `rollback/2`, `seed/0`.
- [x] `ZamHealthWatch.Demo` - `accounts/0`, `password/0`, `ensure_accounts!/0`, `seed_activity!/1`; called from `priv/repo/seeds.exs`.
- [x] `config/runtime.exs` - Neon TLS/SNI, query-string stripping, `RENDER_EXTERNAL_HOSTNAME` fallback for the endpoint host, Logger mailer. `config/prod.exs` - `/health` excluded from `force_ssl`.
- [x] `HealthController` + `GET /health`; demo-aware login notice; new `Layouts.app` header and navigation; new home page; README deployment section.
- [x] Tests: `DemoTest` (accounts created, confirmed, and password-loginable; role/password reset; idempotence; missing-facility error; activity counts; the shaped risk trend; skip when cases exist), `HealthControllerTest`, rewritten `PageControllerTest` (demo credentials, logged-in greeting, navigation visibility by role).

**Status:** 493 tests, 0 failures. Deployed and live at https://zamhealthwatch.onrender.com. Closed. This completes the brief's Transition phase.

Open follow-ups: re-dating the demo cases on boot so `/risk` doesn't drift to "No data" about four weeks after seeding; district-level risk scoring, which would let vaccination coverage feed into it; and linking drug shortages to active outbreaks.

---

## Iteration 15 — Lab result corrections, done the way real systems do them (slice 1 of 4)

**Why this iteration exists:** a question from using the live demo - "when a test is resulted, can it be reviewed or undone in case of a misdiagnosis?" The answer was no. `LabReporting.record_result/3` deliberately rejects a second result, the result's effect on the case is applied once and can't be reversed, and `LabTest` doesn't record who entered a result. Before designing a fix, I looked at how real lab and surveillance software handles corrections: US lab regulation (42 CFR 493.1291(k): notify the requester promptly, issue a corrected report, keep both the original and the corrected one), ISO 15189 (revised reports clearly identified as revisions), FHIR's report statuses (`corrected`, `appended`, `entered-in-error` - three different kinds of change), and SORMAS (case classification kept separate from patient outcome). Agreed plan, three slices:

1. **The case model** (this slice): separate a case's classification from the patient's outcome, and stop counting ruled-out reports as cases.
2. **A lab role and result attribution:** results recorded by a `:lab_officer` (or MOH admin), not by any role, with `resulted_by_id` stored.
3. **Corrections:** an append-only result history (corrected / entered in error, with a required reason), case classification derived from a case's current results so a correction flows through automatically, and notification of the requester. Finding from reading the code that changes the original proposal: public SMS alerts fire when a case is first *reported* (`PublicAlerts.Subscriber` reacts to `{:created, _}`), not when it's lab-confirmed. So the relevant follow-up message isn't "correction of a confirmed alert". It's telling the same subscribers when a reported case is ruled out.

**Decisions (slice 1):**

- **`status` is now only the classification:** `:suspected`, `:confirmed`, or `:not_a_case`. The name stays `status` because that's what surveillance systems call it ("case status" in IDSR and CDC's NNDSS). Before, `:resolved` meant both "recovered" and "a negative lab result ruled it out". Those are opposites: one is a real case, the other never was. A negative result now sets `:not_a_case`.
- **A new `outcome` field** (`:recovered` or `:died`, with `outcome_at`), independent of classification. A suspected case can have an outcome, since a patient can die before a lab result comes back. A ruled-out case can't. An outcome, once recorded, isn't overwritten, the same rule as a lab result: correcting it will be its own audited action, not a silent second click. The case list's "Resolve" button is replaced by "Recovered" / "Died".
- **Manual classification is confirm-only.** A health worker can still confirm a suspected case on clinical or epidemiological grounds (a patient linked to a known cluster, say). Ruling a case out is the lab's call, through a negative result, so there's no manual path to `:not_a_case`.
- **Ruled-out reports aren't counted.** Every aggregate except `count_cases_by_status/0` excludes `:not_a_case`: totals, by disease, by facility (and therefore the map), and the risk trend's weekly buckets. The risk trend matters most, since a cluster of reports the lab ruled out shouldn't read as a rising outbreak. `count_cases_by_status/0` still includes them, so the dashboard can show how many were ruled out. The case list still shows every report. The Epidemiology Dashboard gains "Not a case" and outcome tiles. National Reporting's "Cases (resolved)" column becomes "Ruled out (not a case)" and "Deaths", and its "Cases (total)" is now suspected plus confirmed (`FacilitySummary.case_total/1`, so the CSV and the page can't disagree).
- **Migrating existing data without guessing.** The two old routes into `resolved` left different evidence. A negative lab result set it directly, so a `resolved` case whose latest result is negative becomes `not_a_case`. The "Resolve" button only ever appeared on confirmed cases, so every other `resolved` case becomes `confirmed` with outcome `recovered`. This also converts the live demo's data on the next deploy.
- **`any_cases?/0`** replaces `count_cases() == 0` as the demo's "is the database empty?" check. A database holding only ruled-out cases has zero countable cases but isn't empty.
- **Demo data:** Kabwata's week-2 negative result is now a ruled-out report, so the risk trend sees 1, 1, 3, 5 (still Elevated). The oldest confirmed cholera patient died, and two UTH malaria patients recovered, so every classification and both outcomes appear.

**Built:**

- [x] Migration `split_case_classification_and_outcome`: adds `outcome`/`outcome_at`, converts existing `resolved` rows as above, and indexes `outcome`.
- [x] `Case`: `status` values `:suspected | :confirmed | :not_a_case`; `outcome`, `outcome_at`; `outcome_changeset/2`.
- [x] `CaseManagement`: `record_outcome/3`, `count_cases_by_outcome/0`, `any_cases?/0`; `next_status/1` is confirm-only; countable-only aggregates.
- [x] `LabReporting`: a negative result sets `:not_a_case`.
- [x] `CaseLive.Index` (outcome column, Recovered/Died actions, forged-value handling), `EpidemiologyLive.Index` (Not a case and outcome tiles), National Reporting (columns, `case_total/1`, deaths), `Demo`.
- [x] Tests: `CaseManagementTest` (exclusion from every total, `:not_a_case` still in by-status, outcome counts, `any_cases?/0`, every `record_outcome/3` rule), updated `LabReportingTest`/`LabLive.IndexTest`/`CaseLive.IndexTest` (outcome actions, forged values, ruled-out cases), `NationalReportingTest` (new columns, ruled-out and deaths), `DemoTest` (21 countable of 22 reports, outcomes, the adjusted trend).

**Status:** 506 tests, 0 failures, first run. Migration applied cleanly to the development database. Closed.

---

## Iteration 15 — Lab result corrections (slice 2 of 4)

**Goal:** make results come from the lab, and record who entered each one. Before this, any assigned role could result a test, including the district officer who'd act on it, and a result said when it was entered but not by whom.

**Decisions:**

- **A new `:lab_officer` role, and the only one that can enter results.** That's how real labs work: lab staff enter and verify results, and the clinicians and officers who use them don't. MOH admin is deliberately left out of *entering* results too. The original proposal gives MOH admin a role in *correcting* them (slice 3), which is a different action. `users.role` is a plain string column, so adding the value needed no migration, just the enum and the admin page's role list.
- **The rule lives in one place.** `LabReporting.can_record_results?/1` is the rule, `record_result/3` enforces it, and `LabLive.Index` asks it whether to show the result buttons, instead of keeping its own copy as before ("any assigned role").
- **`record_result/3` takes the recording user, not a role.** Its third argument is now any map with `:id` and `:role` (in practice `current_scope.user`), so it can store who entered the result. It doesn't pattern-match on `%Accounts.User{}`, keeping the same decoupling from `Accounts`'s schema that `CaseManagement.advance_case_status/2` keeps.
- **`resulted_by_id`** on `lab_tests`, a foreign key to `users` with `on_delete: :restrict` (the same audit rule as `requested_by_id`), required by `LabTest.result_changeset/2` for every new result. It's nullable in the database because results entered before this have no record of who entered them, and inventing one would be worse than admitting it. The lab table's new "Resulted by" column says "Not recorded" for those, rather than leaving a blank that reads like missing data.
- **Lab officers see every facility's tests.** In practice one lab serves several facilities (a district lab, a hospital lab taking referrals), so the health-worker facility scoping from Iteration 12 doesn't apply to them.
- **Demo:** a fourth demo account, `lab.officer@example.com`, now enters the demo results. Anyone trying the demo can log in as each side of the workflow: health worker requests a test, lab officer results it, district officer sees the effect.

**Built:**

- [x] Migration `add_resulted_by_to_lab_tests`.
- [x] `User` role `:lab_officer`; "Lab officer" option on `/admin/users`.
- [x] `LabReporting.can_record_results?/1`; `record_result/3` restricted to lab officers, storing `resulted_by_id`.
- [x] `LabLive.Index`: result buttons for lab officers only, a "Resulted by" column, and a clear refusal message for anyone else.
- [x] `Demo`: lab officer account, and demo results entered by it.
- [x] Tests: `LabReportingTest` (lab officer records and is recorded; every other role refused; `can_record_results?/1`), `LabLive.IndexTest` (buttons only for lab officers, "Resulted by" shown, forged events from other roles refused), `DemoTest` (demo results attributed to the lab officer), `NationalReportingTest` updated.

**Status:** 509 tests, 0 failures, first run. Closed.

---

## Iteration 15 — Lab result corrections (slice 3 of 4)

**Re-planned:** this was meant to be the last slice, but corrections plus notifications turned out to be two separate pieces of work. This slice is the correction itself: the history, the recalculated classification, and the screen. The notifications (telling the requester, and the "ruled out" SMS) move to a slice 4, so each stays small enough to test properly.

**Decisions:**

- **Append-only correction history**, in a new `lab_result_corrections` table. Each correction or withdrawal records the previous result, the new one, a required reason, who made it, and when, in the same transaction as the change. Rows are never updated or deleted (no `updated_at`; every foreign key is `:restrict`), and a mistaken correction is fixed by another correction. The earliest entry's `previous_result` is the result as originally issued, which covers US lab regulation's requirement to keep both the original and the corrected report. The lab test's own `resulted_at`/`resulted_by_id` keep saying who issued the original and when.
- **Two kinds of change, following FHIR:** *corrected* (the result was wrong; the test gets status `:corrected` and the new result) and *entered in error* (the result should never have been recorded against this test; the test gets status `:entered_in_error`, keeps the old result for display, struck through, and stops counting). A withdrawn result can't be corrected afterwards; if the test was really done, it's requested again. A correction to the same result is refused as `:unchanged`, so the history doesn't fill with no-ops.
- **A reason is required, at least 10 characters after trimming.** Long enough that "typo" doesn't pass. An unexplained correction is exactly the kind of record an audit can't make sense of later.
- **Who can correct:** lab officers (who issue results) and MOH admins (oversight, for when the lab itself can't). Not district officers or health workers. A correction changes a case's classification for everyone, so it needs the same authority as issuing the result. `can_correct_results?/1` is the single rule; the screen asks it, and `correct_result/4`/`withdraw_result/3` enforce it.
- **Classification is now recalculated from all of a case's current results, not pushed by each new one.** This is the change that makes corrections work without an "undo". `LabReporting` works out a verdict from the case's resulted and corrected tests (pending and withdrawn ones don't count): any positive, else any negative, else none. `CaseManagement.classification_for/2` turns that, plus whether a person confirmed the case clinically, into a classification. Positive confirms. Negative rules out, even over a clinical confirmation, because a laboratory finding outranks a clinical impression. With nothing conclusive, a clinical confirmation stands. Otherwise the case is suspected. Since the answer depends only on those facts and never on the previous status, every correction lands correctly. One deliberate change from before: with conflicting results on different tests of the same case, a positive now wins regardless of order, where before the latest result did. A negative test can miss a real infection; a positive rarely invents one.
- **Clinical confirmation became its own fact** (`cases.clinically_confirmed_at`, set by the Confirm button). Without it, withdrawing a positive result on a case a health worker had also confirmed would wrongly drop it back to "suspected". The migration backfills it for every case that's confirmed today with no positive lab result behind it, since that can only have been a manual confirmation.
- **Correction timestamps use microseconds.** The order of the history is the audit trail, and two corrections in the same second would otherwise sort ambiguously.
- **National Reporting** counts a corrected result as issued and a withdrawn one as not (`FacilitySummary.issued_lab_results/1`).
- **Demo:** one Kabwata result is now issued positive, then corrected to negative with a reason, so `/labs` shows a real correction history. UTH's confirmations go through the Confirm path, so they're recorded as clinical.

**Built:**

- [x] Migration `add_lab_result_corrections` (corrections table; `cases.clinically_confirmed_at` with backfill).
- [x] `LabReporting.LabResultCorrection` schema and changeset (reason trimmed, 10-1000 characters; new result required for corrections, empty for withdrawals).
- [x] `LabTest`: statuses `:corrected` and `:entered_in_error`; `correction_changeset/2`, `withdrawal_changeset/1`.
- [x] `LabReporting`: `can_correct_results?/1`, `correct_result/4`, `withdraw_result/3`, `list_corrections/0`, `list_corrections_for_lab_test/1`, and verdict-based recalculation after every result change.
- [x] `CaseManagement`: `classification_for/2`, `apply_lab_verdict/2`; Confirm records `clinically_confirmed_at`.
- [x] `LabLive.Index`: Correct/Withdraw actions, a correction panel (result picker and reason, with validation errors shown inline), Corrected/Withdrawn badges, struck-through withdrawn results, and a facility-scoped correction history.
- [x] Tests: `LabReportingTest` (correct, correct twice in order, MOH admin, other roles refused, reason validation leaves everything unchanged, unchanged and not-correctable refusals, broadcast, a positive on another test still confirming, withdrawal, clinical confirmation surviving a withdrawal, nothing after withdrawal), `CaseManagementTest` (every `classification_for/2` rule, `apply_lab_verdict/2`, clinical confirmation recorded), `LabLive.IndexTest` (correct and withdraw through the panel, a too-short reason shown as an error, MOH admin access, district officer refused even with forged events), `NationalReportingTest`, `DemoTest`.

**Status:** 538 tests, 0 failures, first run. Migration and backfill applied cleanly. Closed.

---

## Iteration 15 — Lab result corrections (slice 4 of 4)

**Goal:** the notifications. A correction is only half done if the people who acted on the wrong result never find out. Two audiences: the person who requested the test (lab regulation: "promptly notify the authorized person ordering the test"), and the public alert subscribers who were warned when the case was first reported.

**Decisions:**

- **Requester notices, kept until acknowledged.** `LabReporting.list_correction_notices/1` returns corrections and withdrawals of results on tests a user requested that they haven't marked as seen yet. Corrections they made themselves are excluded, since they already know. The lab screen shows each one (case, old → new, reason) with a "Mark as seen" button. The Portal shows a count with a link to the lab screen, for any user, with or without a facility, because anyone can request a test. A notice stays in front of the requester instead of being one line in a history they might never look at, because their view of the old result may already have shaped what they did for the patient.
- **Acknowledgement is its own recorded fact** (`lab_correction_acknowledgements`: who, which correction, when), kept beside the correction history rather than written into it, so correction rows are still never updated. Only the requester can acknowledge, since a notice exists so *they* know. Acknowledging twice is harmless (unique index plus `on_conflict: :nothing`). A later correction to the same test is a new notice, even if the earlier one was seen.
- **Public follow-ups for ruled-out cases.** Alerts go out when a case is first *reported* (`AlertWorker`, unchanged). Now, when a case moves into `:not_a_case`, subscribers get "the Cholera case reported at Kabwata Clinic on 03 Oct 2026 has been ruled out by laboratory testing". When a correction moves a case back *out* of `:not_a_case`, they get a plain correction: "we said … had been ruled out. That was wrong - the case is confirmed / under investigation again." A case simply being confirmed sends nothing, because the original alert already gave the right advice. `ReclassificationAlertWorker` does the sending, enqueued by `PublicAlerts.Subscriber`.
- **Reclassifications get their own PubSub topic** (`"case_reclassifications"`, `{:reclassified, case, previous_status}`), sent only when `status` actually changes. Not on `"cases"`: every LiveView subscribed there pattern-matches `{:created, _}`/`{:updated, _}` only, and a new message shape on that topic would crash each of them. Only the alert subscriber, which cares about the *transition*, listens.
- **SMS delivery shared, not copied.** `PublicAlerts.deliver_to/2` now holds the send-and-retry rule (only "every send failed" is worth retrying), used by both `AlertWorker` and the new worker, so the two can't drift apart.
- **Demo:** the demo correction is on a test the demo health worker requested, so logging in as `health.worker@example.com` shows a real notice on the Portal and the lab screen. Known demo limitation: once any visitor marks it as seen, it's gone for everyone until the database is reseeded. Demo accounts are reset on boot, but their acknowledgements aren't.

**Built:**

- [x] Migration `add_lab_correction_acknowledgements`; `LabReporting.LabCorrectionAcknowledgement`.
- [x] `LabReporting.list_correction_notices/1`, `acknowledge_correction/2`.
- [x] `CaseManagement.subscribe_reclassifications/0` and reclassification broadcasts from every status change.
- [x] `PublicAlerts.deliver_to/2` (extracted from `AlertWorker`); `PublicAlerts.ReclassificationAlertWorker`; `Subscriber` enqueues it for transitions into and out of `:not_a_case`.
- [x] `LabLive.Index` notices panel with "Mark as seen"; `PortalLive.Index` notice count with a link.
- [x] Tests: `LabReportingTest` (requester sees it, nobody else and not the corrector, acknowledge clears it and is idempotent, only the requester can, unknown/malformed ids, a second correction is a new notice), `CaseManagementTest` (reclassification broadcast from a lab verdict and from Confirm, none when unchanged), `SubscriberTest` (follow-up on ruled out, correction on reinstatement, nothing on a plain confirmation), new `ReclassificationAlertWorkerTest` (all three messages, delivery to every subscriber), `LabLive.IndexTest` (requester sees and clears the notice, others don't see it, forged acknowledgement refused), `PortalLive.IndexTest` (count and link shown only when there's something to review).

**Status:** 559 tests, 0 failures, first run. Migration applied cleanly. Closed. With this slice, Iteration 15 is complete: corrections that keep the original result, require a reason, recalculate the case's classification, and tell the people affected.

---

## Iteration 16 — Demo reset on boot

**Goal:** keep the public demo fresh. Two problems showed up once the demo had been live for a while. The live database was seeded before Iteration 15, and `seed_activity!/1` only seeds an empty database, so the demo correction (and its notice for the health worker) never appeared on the live site. And the risk trend is dated relative to when the data was seeded, so about four weeks later every facility drifts to "No data". Both are the Iteration 14 follow-up "re-date the demo cases", plus the Iteration 15 known limitation that a notice marked as seen is gone for every later visitor.

**Decisions:**

- **Wipe and reseed on every boot, rather than re-dating the existing rows.** Re-dating would fix the trend but not the rest: a visitor who rules out a case, records a death, or marks the correction notice as seen leaves the demo that way for everyone after them. Reseeding from scratch fixes both, and it reuses `seed_activity!/1` unchanged. Render's free instance restarts whenever it has been idle for 15 minutes, so in practice each visitor after a quiet spell gets the same fresh demo, dated from that moment. The trade-off accepted: anything a visitor changes is gone at the next restart. For a shared public demo that is the intended behaviour, and the home page says so.
- **Opt-in, off by default.** `DEMO_RESET_ON_BOOT=true` turns it on (read in `config/runtime.exs`, exposed as `Demo.reset_on_boot?/0`). Without it, nothing is ever wiped, so a developer's database and any deployment with real data are safe. `reset_activity!/0` itself is unconditional; the check lives in `priv/repo/seeds.exs`, the one caller, and the tests call the function directly.
- **What gets wiped:** cases, lab tests, corrections and acknowledgements, drug stock, capacity reports, vaccination records, and alert subscribers, deleted children-first so the `:restrict` foreign keys hold, in one transaction so a failure leaves everything as it was. Alert subscribers are included because on a public demo they're visitors' phone numbers, which shouldn't outlive the demo session. Alert jobs that haven't run yet are deleted too, since a job for a case that no longer exists would fail on every retry. **Kept:** user accounts (the demo accounts are reset separately by `ensure_accounts!/0`), districts, and facilities.
- **Lives in `Demo`, not in the contexts.** A "delete everything" function on `CaseManagement`, `LabReporting`, and the rest would be a dangerous public API that only a demo needs. `Demo` already used `Repo` directly for two seeding-only jobs (backdating cases, setting demo passwords); this is the third, documented the same way.
- **No second safety check,** such as refusing to reset when non-demo users exist. Visitors can register accounts on the demo, and the demo MOH admin can give them roles, so any such check would block the reset on the one deployment that needs it. The explicit, clearly named environment variable is the guard.

**Built:**

- [x] `Demo.reset_on_boot?/0`, `Demo.reset_activity!/0`; `priv/repo/seeds.exs` resets before seeding when the flag is on.
- [x] `config/runtime.exs` reads `DEMO_RESET_ON_BOOT`; `render.yaml` sets it for the demo service.
- [x] Home page notice (`#demo-reset-notice`) when the deployment resets on boot. README deployment section.
- [x] Tests: `DemoTest` (every kind of activity cleared; accounts, districts, and facilities kept; per-table counts returned; waiting alert jobs removed; reset plus seed brings back a correction notice that had been marked as seen; flag off unless configured), `PageControllerTest` (notice shown only when the flag is on).

**Status:** 568 tests, 0 failures, first run. Closed. Deployed: Render picked `DEMO_RESET_ON_BOOT` up from `render.yaml` through the Blueprint sync, so no dashboard change was needed. The first boot logged "cleared 46 rows of demo activity", the home page shows the reset notice, and the demo health worker saw the correction notice on the Portal for the first time. Still to confirm: that the free instance actually spins down when idle despite Render's `/health` checks every 5 seconds. If it doesn't, the reset only runs on deploys, and the fix is to also reset when the demo data is older than a set age.

---

## Iteration 17 — District-level risk scoring (slice 1 of 2)

**Goal:** the brief's "district-level outbreak risk scoring", which Iteration 2's Predictive Analytics slice scoped down to per-facility scoring because facilities didn't have a district yet (Iteration 3 then gave them one). This slice adds the district read, trending each disease separately. Slice 2 brings in vaccination coverage.

**Decisions:**

- **Per district and per disease, not all diseases added together.** Real surveillance thresholds are per disease and per district: Zambia's IDSR works that way, and ZNPHI's automated alert thresholds (piloted from January 2025) go to district surveillance officers. Adding diseases together lets a rise in one hide behind a fall in another. Cholera going 1, 2, 3, 4 a week while malaria goes 4, 3, 2, 1 adds up to a flat 5 a week, which the facility read calls Stable. A test pins exactly that case down.
- **A district's tier is its worst disease's tier,** and the page lists each disease's trend under it, worst first, so the reason for the tier is visible. A district with no cases in the window is "No data", as for facilities.
- **Same arithmetic as the facility read:** four 7-day windows, an Nx least-squares slope, and Elevated at 0.5 or more extra cases a week. The windows are now built once (`weekly_windows/1`) and counted two ways, rather than duplicated.
- **The facility read stays.** Hospital capacity is reported per facility, and a district officer still needs to see which clinic is under strain. `/risk` shows the district table first and the facility table below it.
- **Facilities without a district aren't counted in any district.** They still appear in the facility table. The seeded reference facilities all have a district.
- **Counting stays in `CaseManagement`:** a new `count_cases_by_facility_and_disease_between/2`, with the same window, the same exclusion of ruled-out cases, and zero-omission as `count_cases_by_facility_between/2`. `PredictiveAnalytics` maps facilities to districts through `Geography`'s public API.

**Built:**

- [x] `CaseManagement.count_cases_by_facility_and_disease_between/2`.
- [x] `PredictiveAnalytics.list_district_risks/1`; `DistrictRisk` and `DiseaseTrend` structs; shared `weekly_windows/1`.
- [x] `RiskLive.Index`: "By district" table (`#district-risks`, one row per district, each disease's weekly counts and tier) above the facility table, updating live on new and updated cases.
- [x] Tests: `CaseManagementTest` (grouping by facility and disease, ruled-out cases skipped, window edges), `PredictiveAnalyticsTest` (empty district, same disease added across facilities, rising and falling diseases kept apart while the facility read sees a flat line, facility without a district left out, out-of-window case ignored, sort order), `RiskLive.IndexTest` (district row with per-disease trends, no-data district, live update, empty state).

**Status:** 579 tests, 0 failures, first run. Closed.

---

## Iteration 17 — District-level risk scoring (slice 2 of 2)

**Goal:** the brief's "vaccination coverage feeds risk scoring", deferred since Iteration 6 because coverage is per district and risk was per facility. Slice 1 made risk per district, so the two can now meet.

**Decisions:**

- **Coverage applies only to the disease its vaccine prevents.** Of the five diseases cases can be reported for, only measles has an antigen in the system (measles-rubella). There's no cholera, malaria, typhoid, or COVID-19 antigen in `VaccinationRecord`'s list. Applying measles-rubella coverage to cholera risk would be invented epidemiology, so `@vaccine_for` maps measles to measles-rubella and nothing else. Adding a pair there is all it takes to extend it.
- **Below 95% is an immunity gap.** 95% is the commonly cited level needed to stop measles spreading, and population immunity is one of the four categories in WHO's district-level measles programmatic risk assessment tool. The tool's other three categories (surveillance quality, programme performance, threat assessment) need data this system doesn't collect, so this is one part of that tool, not a copy of it. Logged as a known limitation.
- **Measles cases plus a gap raise measles, and so the district, to a new third tier, High,** whatever the slope says: cases are already circulating in a population that can't stop them. The trend line records which coverage figure caused it, and the page says so ("Cases with Measles-Rubella coverage at 47.5%"). A facility's own tier is never High; only the district read has the coverage to know.
- **A gap without measles cases is shown but changes no tier.** It's a vulnerability, not an outbreak. A district with no coverage record shows "No coverage data" and isn't treated as either safe or at risk.
- **Latest record wins,** whatever the campaign, the same way capacity uses each facility's latest report. A district's figure is whatever it reported most recently. `VaccinationMonitoring.latest_coverage_by_district/1` owns that query.
- **Badge colours:** High is the only red. Elevated drops to amber, so the three tiers can be told apart at a glance.
- **Demo data:** two recent measles cases at Monze Mission Hospital, where demo measles-rubella coverage is 47.5%. The live demo now shows all three cases: Monze High (measles and a gap), Lusaka Elevated (cholera, with an 84% gap that changes nothing because there's no measles), and Ndola Stable (measles, but no coverage record).

**Built:**

- [x] `VaccinationMonitoring.latest_coverage_by_district/1`.
- [x] `PredictiveAnalytics`: `@vaccine_for`, `immunity_threshold/0`, `ImmunityStatus` struct, `DistrictRisk.immunity`, `DiseaseTrend.escalated_by`, the `:high` tier.
- [x] `RiskLive.Index`: Immunity column, the reason shown under a raised disease, High/Elevated colours, live updates on new coverage records.
- [x] Demo: measles cases at Monze; `DemoTest` updated for 24 reports and the district tiers.
- [x] Tests: `VaccinationMonitoringTest` (latest per district, other antigens ignored), `PredictiveAnalyticsTest` (gap raises measles to High, 95% doesn't, no record doesn't, gap without measles changes nothing including other diseases, latest record used, High sorts above Elevated), `RiskLive.IndexTest` (High with its reason and the gap badge, "No coverage data", live update on a new coverage record), `DemoTest` (Monze High, Lusaka Elevated, Ndola Stable).

**Status:** 590 tests, 0 failures, first run. Closed. With this slice, Iteration 17 is complete: risk is scored per district and per disease, and measles-rubella coverage raises measles risk where it leaves an immunity gap.

---

## Iteration 18 — Correcting a recorded outcome

**Goal:** close the gap Iteration 15 left on purpose. Once Recovered or Died was recorded on a case it couldn't be changed: `record_outcome/3` refuses to overwrite, so a mis-click can't silently replace a death, but there was no audited way to fix a real mistake. A wrongly recorded death matters most, because it shows in Deaths on the dashboards and in the national CSV.

**Decisions:**

- **Same design as lab result corrections (Iteration 15),** since that one already follows real-world practice: the original value is never overwritten without a trace, a reason is required, and the history is append-only.
- **Two actions.** Change the outcome (Died to Recovered or back), or remove it as entered in error (recorded on the wrong patient's case, say), which returns the case to "no outcome yet" so the right one can be recorded afresh.
- **Only district officers and MOH admins can correct.** A supervisory check, so the person who entered a death can't quietly reverse it. This mirrors lab corrections, where lab officers and the MOH admin correct. A health worker sees the history of their own facility's cases but no correction form.
- **Who recorded the outcome is now stored** (`cases.outcome_recorded_by_id`). Until now `record_outcome/3` only checked the recorder's role and stored nobody, so a correction couldn't say whose entry it corrected. Its third argument is now the user (`%{id, role}`), the same shape `LabReporting.record_result/3` takes. Outcomes recorded before this migration have no recorder; the column is nullable for them.
- **A correction keeps the original entry's time and author;** the correction row records the corrector. Removing an outcome clears all three outcome fields.
- **Counts follow automatically.** Deaths on the dashboards and in National Reporting are worked out from each case's current outcome, so nothing else needed changing.
- **The requester isn't notified,** unlike a lab correction. Whoever recorded an outcome didn't make a clinical decision based on it, the way a clinician does on a lab result. Possible later if wanted.
- **Fixed on the way: live case scoping.** `CaseLive.Index` streamed in every broadcast case, so a health worker's list picked up live reports from other facilities until they reloaded the page. New and updated cases are now only added when they're in the viewer's scope. A forged request to open the outcome panel for another facility's case is refused.
- **Demo:** a third UTH malaria patient is recorded as died by the district officer and then corrected to recovered by the MOH admin, so the live demo shows a "Corrected" case and a real history. `Demo.reset_activity!/0` deletes outcome corrections before cases, for the foreign key.

**Built:**

- [x] Migration `add_case_outcome_corrections`: `cases.outcome_recorded_by_id`, `case_outcome_corrections` table.
- [x] `CaseManagement.OutcomeCorrection` schema; `Case.outcome_correction_changeset/2`, `outcome_withdrawal_changeset/1`.
- [x] `CaseManagement`: `record_outcome/3` now takes the recorder; `can_correct_outcomes?/1`, `correct_outcome/4`, `withdraw_outcome/3`, `list_outcome_corrections_for_case/1`, `list_outcome_corrected_case_ids/0`.
- [x] `CaseLive.Index`: "Correct outcome" button, outcome panel (`#outcome-panel`: current outcome and who recorded it, the correction form, `#outcome-history`), "Corrected" marker on corrected cases, live scoping fix.
- [x] Demo outcome correction.
- [x] Tests: `CaseManagementTest` (correction and history, removal and re-recording, roles, no outcome, unchanged, reason required with nothing changed, invalid outcome, correcting a correction, counts and the corrected-case list follow), `CaseLive.IndexTest` (officer corrects and the history shows it, removal brings back the outcome buttons, short reason refused, health worker sees no button and a forged correction is refused, panel refused for another facility's case, live list scoped to the health worker's facility), `DemoTest` (demo correction, reset count), existing `record_outcome` callers updated.

**Status:** 604 tests, 0 failures, first run. Migration applied cleanly. Closed.

---

## Iteration 19 — Drug shortages linked to outbreaks

**Goal:** tell an emergency shortage from a routine restock. `/drugs` flags any medicine below its reorder level, and `/risk` shows outbreaks, but nothing connected them. Artemether-lumefantrine short at a clinic with no malaria can wait for the next delivery. ORS short at a clinic in a cholera outbreak can't.

**Decisions:**

- **A medicine-to-disease map, limited to the five medicines tracked** (`PredictiveAnalytics.@medicines_for`), checked against clinical guidance:
  - Cholera: ORS and IV fluids (Ringer's lactate). Rehydration is the treatment: ORS for mild or moderate dehydration, Ringer's lactate IV for severe. Antibiotics are only for severe cases, and the first-line ones (doxycycline, azithromycin) aren't tracked. Ciprofloxacin is deliberately left out because of reduced susceptibility.
  - Malaria: artemether-lumefantrine, first-line for uncomplicated malaria.
  - Typhoid: ciprofloxacin and ceftriaxone, both among WHO's recommended options, with local resistance deciding between them.
  - Measles and COVID-19: no tracked medicine, so never an alert. Nothing invented to fill the gap.
- **The rule:** a supply alert when a facility has had cases of a disease in the last four weeks (the same window as risk) and a medicine for that disease is below its reorder level. Each alert carries the disease's four-week trend at that facility, and alerts sort worst trend first.
- **Latest stock wins,** per facility and medicine (`DrugAvailability.latest_stock_by_facility_and_medicine/0`), so a restock clears an alert. A medicine a facility has never reported isn't assumed to be short.
- **Shown on `/risk`** (a "Supply alerts" table between the district and facility tables) and **on `/drugs`** (a banner, limited to the health worker's own facility). Both update live on new stock records and new or reclassified cases.
- **Fixed on the way: live stock scoping on `/drugs`,** the same bug Iteration 18 fixed on `/cases`. A health worker's list picked up other facilities' submissions live until a reload.
- **Demo:** Kabwata Clinic's cholera outbreak raises alerts for ORS (40 / 100) and IV fluids (15 / 30), and UTH's typhoid case for ceftriaxone (20 / 50). Monze's artemether-lumefantrine shortage (30 / 60) stays quiet: its only malaria case is six weeks old. That's the routine restock the rule exists to tell apart.

**Known follow-ups, not fixed here:**

- The same live-scoping bug exists on `/hospital`, `/labs`, and `/vaccinations`: each one's `handle_info({:created, _})` streams in every broadcast record. Checked, not yet fixed. One small pass with a test each.
- National Reporting's "Drug stock shortages" count is taken over every stock record a facility ever submitted, not its latest per medicine, so a shortage that has since been restocked still counts. `latest_stock_by_facility_and_medicine/0` is the fix.

**Built:**

- [x] `DrugAvailability.latest_stock_by_facility_and_medicine/0`.
- [x] `PredictiveAnalytics.list_supply_alerts/1`, `medicines_for/1`, `SupplyAlert` struct; shared `facility_disease_buckets/1`.
- [x] `RiskLive.Index` supply alerts table (`#supply-alerts`); `DrugLive.Index` banner (`#supply-alerts`) and live scoping fix.
- [x] Tests: `DrugAvailabilityTest` (latest per facility and medicine), `PredictiveAnalyticsTest` (alert fields and trend, in stock, no recent cases, unrelated medicine and measles, restock clears it, shortage at another facility, sort order), `RiskLive.IndexTest` (alert row, live alert on a new shortage), `DrugLive.IndexTest` (health worker sees only their facility's alert, no banner without one, live alert from a new case, live list scoping), `DemoTest` (the three demo alerts, Monze quiet).

**Status:** pending `mix test` verification.

---
