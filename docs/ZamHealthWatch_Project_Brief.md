# ZamHealthWatch — Project Brief

*A Public Health Intelligence Platform for Zambia*

Personal portfolio project. Built to actually be used, not to satisfy a grading rubric — no supervisor, no submission deadline, no 80–100 page report requirement. What follows replaces the original UNZA FYP proposal as the live spec for this build.

---

## 1. Vision

Zambia's disease surveillance is still largely paper-first: a case is written on a form at a clinic, physically carried or phoned up to a District Health Office, then compiled again before it reaches the Ministry of Health. By the time a signal is visible at national level, an outbreak has often already moved past the point where early intervention would have mattered most. The 2017–2018 Lusaka cholera outbreak (5,000+ infections, at least 83 deaths) and a persistently high malaria burden (28% national parasite prevalence, 2023 Malaria Indicator Survey) are the concrete cost of that lag.

ZamHealthWatch is not "an outbreak tracker" — that undersells it and boxes it into a single dataset and a single view. It's a **Public Health Intelligence Platform**: a modular system where surveillance, case management, lab results, vaccination coverage, drug stock, hospital capacity, and public alerts are all connected views over the same underlying reality, not twelve disconnected apps. The closest real-world reference point is DHIS2, the modular health information platform already deployed across African ministries of health, Zambia's included — ZamHealthWatch is a personal, from-scratch reimagining of that category, not a novel invention of it.

## 2. Why This Project

Two goals, held simultaneously:

**Solve a real problem, credibly.** Every module in scope maps to an actual, documented gap in Zambia's current disease surveillance workflow, not a feature invented to pad a module list. If a module doesn't trace back to something in Section 1, it doesn't belong in scope.

**Build a portfolio piece that demonstrates real engineering judgment**, not just CRUD-with-a-nice-UI. That means: a domain model that's actually been thought through (not just tables that mirror a spreadsheet), a real-time layer that's architecturally justified rather than bolted on, and a development process — iterative, risk-driven, one deliberately-scoped slice at a time — that's visible in the commit history and the docs, not just claimed in a README. Concretely, the process follows Craig Larman's iterative/evolutionary approach from *Applying UML and Patterns*: risk-driven and value-driven iteration ordering, architecturally-significant use cases tackled early, and GRASP-style responsibility assignment at the module/object level. Iteration planning itself is deliberately **not** part of this document — that's next, once this brief is settled.

## 3. Problem Statement

Zambia lacks a centralised, real-time system that connects disease case detection, laboratory confirmation, vaccination coverage, drug and hospital capacity, and public risk communication into one operational picture. Each of these currently lives in its own paper trail or, at best, its own disconnected spreadsheet, which means a district health officer has no single place to see "cases are rising, the lab backlog is confirming it, drug stock in that district is low, and the nearest hospital is near capacity" as one connected signal rather than four separate ones discovered too late.

## 4. Scope — The Twelve Modules

Each module below is a bounded, cohesive unit — in implementation terms, a Phoenix context that owns its own schemas and exposes a narrow public API to the rest of the system (more on why in Section 6).

| Module | What it owns |
|---|---|
| **Disease Surveillance** | Case ingestion and aggregation by facility, district, disease; the core signal everything else reacts to. |
| **Case Management** | Individual patient case lifecycle — suspected → confirmed → resolved, contact tracing links. |
| **Laboratory Reporting** | Lab test requests and results, linked back to cases; confirms or downgrades surveillance signals. |
| **Vaccination Monitoring** | Coverage rates by district/antigen/campaign; feeds risk scoring (low coverage = higher outbreak risk). |
| **Drug Availability** | Stock levels of essential medicines by facility; flags shortages that compound an active outbreak. |
| **Hospital Capacity** | Bed occupancy, ICU availability, admission rates by facility — the "can the system absorb this" view. |
| **Public Alerts** | Threshold-triggered and model-triggered notifications out to health workers and the public via SMS/USSD/web. |
| **Health Worker Portal** | Facility-level login, case entry, guidance content — the primary human interface at the point of care. |
| **Epidemiology Dashboard** | Cross-module analytics and trend visualisation for district/national officials. |
| **Predictive Analytics** | District-level outbreak risk scoring from historical case, vaccination, and environmental data. |
| **GIS Mapping** | Geospatial case density, hotspot detection, district/province boundary overlays. |
| **National Reporting** | Aggregated, exportable reporting for MOH-level consumption — the rollup of everything else. |

Scoping honesty: this is DHIS2-scale ambition built by one person. It is intentionally *not* being built as twelve parallel workstreams — see Section 5 on how the risk of that gets managed.

## 5. Development Approach

**Iterative and evolutionary, not waterfall.** Requirements and design are not fully specified before implementation starts — they emerge through iterations, refined by what building the previous slice actually taught. This is the central UP idea from Larman: a plan for the whole project stays deliberately high-level (a phase plan, not a task-by-task schedule), and only the *next* iteration gets planned in real detail.

**Risk-driven and value-driven ordering.** Early iterations are chosen to (1) drive down the highest-risk unknowns and (2) produce something real and demoable. For this project the two biggest risks are architectural (does the core domain model — cases, facilities, districts, users — actually hold up once six modules depend on it) and personal (this is a first Elixir project, so language/OTP/Phoenix fluency is itself a risk to retire early, not late). Both get front-loaded rather than discovered in module eight.

**Phases, adapted from the UP's four (Inception → Elaboration → Construction → Transition):**

- *Inception* is a feasibility pass, not a requirements phase — this document, plus enough of a domain model and architecture sketch to know the project is buildable and worth doing. That's most of what's in this brief.
- *Elaboration* iteratively builds and stabilizes the **core architecture** against the highest-risk, highest-value slice (Disease Surveillance + Case Management — see the Personal Vision doc's iteration order for the fuller sequence), resolving the big unknowns (Elixir/Phoenix fluency, the domain model, the real-time layer) before the remaining modules are considered "easy" additions.
- *Construction* is where the lower-risk modules (Lab Reporting, Vaccination, Drug Availability, Hospital Capacity) get built quickly against a now-proven architecture.
- *Transition* is deployment/demo polish — a hosted, working instance a recruiter or collaborator can actually click through.

**Object/module design discipline: GRASP.** Each Phoenix context is assigned responsibilities the way Larman's GRASP patterns argue for: *Information Expert* (the context that holds the data answers the questions about it — Vaccination Monitoring, not Disease Surveillance, decides coverage rates), *High Cohesion / Low Coupling* (a context talks to another context through its public API, never by reaching into its schemas directly), *Creator* (a Case is created by the context that aggregates it — Case Management — not by whichever module happens to need one), and *Controller* (each system operation, like "an SMS report comes in," has one clear entry point coordinating the work, not logic scattered across the ingestion pipeline).

Sprint/iteration-level planning is deliberately out of scope for this document — that's the next conversation, once this brief is agreed.

## 6. System Architecture

**Language & runtime:** Elixir on the BEAM/OTP. First Elixir project — chosen deliberately, and it's a good fit for a meaningful chunk of this system, not a stretch: OTP supervision trees suit a system that has to keep running (alert monitors, ingestion pipelines) more naturally than most alternatives, and Phoenix LiveView removes the need for a separate React frontend entirely for most modules.

**Web layer:** Phoenix, with **LiveView** for real-time server-rendered UI (dashboards, alert feeds, hospital capacity views update live without a hand-rolled REST+polling layer) and **Phoenix PubSub** as the internal event bus connecting modules (e.g., a new confirmed case in Disease Surveillance publishes an event; Public Alerts and the Epidemiology Dashboard subscribe).

**Database:** PostgreSQL via **Ecto**, with the **PostGIS** extension and the `geo_postgis` Ecto adapter for geospatial queries (hotspot detection, district boundary containment) backing the GIS Mapping module.

**Background work & scheduling:** **Oban** (Postgres-backed job queue) for alert-threshold checks, scheduled report generation, and SMS delivery retries — no separate queue infrastructure needed.

**Data ingestion:** **Broadway** for the SMS/USSD inbound pipeline, giving backpressure handling if report volume spikes during an actual outbreak (the exact moment the original architecture would be under the most load).

**Predictive Analytics:** attempt Elixir-native first — **Nx** (tensors), **Axon** (neural nets), **Explorer** (dataframes, the Elixir analogue of pandas) — and treat it as the one module where "stay in Elixir" is a stretch goal rather than a given. Classical time-series forecasting (the Prophet-equivalent job) is meaningfully more mature in Python's ecosystem; the documented fallback is a small dedicated Python service reached over HTTP, kept deliberately thin and swappable, rather than quietly reintroducing a parallel Flask stack.

**Mapping frontend:** Leaflet.js, wired in as a LiveView JS hook (no separate SPA needed) rendering GeoJSON district/province boundaries.

**SMS/USSD gateway:** Africa's Talking API — unchanged from the original proposal, since this choice was never language-specific; consumed from Elixir via `Req` or `Tesla`.

**Auth:** `mix phx.gen.auth` for the Health Worker Portal login; Guardian (JWT) only if/when an external API consumer (e.g., a future MOH integration) needs token-based auth separate from session-based portal login.

**Testing & quality:** ExUnit for unit/integration tests, `StreamData` for property-based testing of the domain logic (case state transitions, risk scoring are good candidates), Phoenix's built-in LiveView test tooling for UI flows, Credo for style/lint, Dialyzer for static analysis — all standard portfolio-quality signals in the Elixir ecosystem.

**Observability:** Telemetry + Phoenix LiveDashboard for runtime visibility; plain structured logging is enough at this scale, no need for a separate APM vendor.

**Deployment:** Fly.io or Gigalixir — both are strong fits for BEAM applications specifically (multi-region, clustering support), a better match than the original Render/Railway choice now that the stack is Elixir-native rather than a three-service polyglot split.

**CI:** GitHub Actions running `mix test`, `mix format --check`, Credo, and Dialyzer on every push.

## 7. Non-Functional Considerations

- **Low-connectivity access** is still handled the same way as originally proposed — the SMS/USSD channel via Africa's Talking exists specifically because a meaningful share of the target users won't have reliable internet.
- **Reliability**: OTP supervision trees mean a crashed ingestion worker or alert checker restarts without taking the whole app down — a natural fit for "this needs to keep running during the exact event that's stressing it."
- **Data model integrity**: cases, facilities, districts, and users are the shared core every module depends on — this is the piece that gets the most design scrutiny before anything else is built (see Section 5).

## 8. Out of Scope / Limitations

- This is a portfolio-grade prototype, not a system seeking MOH deployment. No procurement process, shortcode registration, or ministry partnership is implied or required to consider the project "done."
- Predictive Analytics accuracy depends entirely on the quality and completeness of whatever historical data is used for training (WHO AFRO / Zambia MOH published bulletins) — this was a real limitation in the original proposal and remains one here.
- SMS/USSD integration is demonstrated against Africa's Talking's sandbox environment; a live shortcode is out of scope.
- Security hardening sufficient for real patient data at scale (encryption at rest, audit logging, access control depth) is treated seriously in design but not pursued to the level a real deployment would require.

## 9. References

- World Health Organization (2023). *Zambia: Disease Outbreak News.* Geneva: WHO.
- Zambia Ministry of Health (2022). *Annual Health Statistical Bulletin.* Lusaka: MOH.
- Africa Centres for Disease Control and Prevention (2023). *Africa CDC Integrated Disease Surveillance and Response.* Addis Ababa: Africa CDC.
- Brownstein, J. S., Freifeld, C. C., & Madoff, L. C. (2009). Digital disease detection — harnessing the Web for public health surveillance. *New England Journal of Medicine*, 360(21), 2153–2157.
- Africa's Talking (2024). *SMS and USSD API Documentation.* Nairobi: Africa's Talking Ltd.
- Larman, C. (2004). *Applying UML and Patterns: An Introduction to Object-Oriented Analysis and Design and Iterative Development* (3rd ed.). Prentice Hall. — methodology and GRASP grounding for Section 5.
- DHIS2 (District Health Information Software 2) — real-world reference architecture for a modular health information platform, widely deployed across African ministries of health.

## 10. What's Next

This brief covers Inception: vision, scope, architecture, and development approach. It deliberately stops short of iteration/sprint planning — the next step is picking the first architecturally-significant, high-risk, high-value slice (almost certainly the core domain model, then Disease Surveillance + Case Management) and planning that one iteration in real detail, rather than speculatively planning all of them now.
