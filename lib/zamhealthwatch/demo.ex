defmodule ZamHealthWatch.Demo do
  @moduledoc """
  Demo accounts and demo activity for the public, deployed instance of
  this portfolio prototype (Iteration 14).

  Two problems this solves, both specific to running a public demo
  rather than a real system:

    * **Nobody could log in otherwise.** Registration and login send a
      magic link by email, and the deployed app has no real email
      provider - `Swoosh.Adapters.Local` only stores mail in memory. So
      instead of wiring up email, there's one password-login account per
      role (`accounts/0`), with the credentials published on the home
      page. They aren't secrets - they're meant to be shared - which is
      why they live in source control in plain text.
    * **An empty database demos nothing.** `seed_activity!/1` adds a
      small, deliberately shaped dataset - a rising cholera cluster at
      Kabwata Clinic, a steady malaria load at UTH, drug shortages, a
      hospital over capacity, one district with low measles coverage - so
      every screen, including `/risk` and `/reports/national`, has
      something real to show.
    * **Shared demo data goes stale and gets used up** (Iteration 16).
      The risk trend is dated relative to when the data was seeded, so
      it drifts to "No data" about four weeks later, and one visitor's
      changes (a ruled-out case, a correction notice marked as seen) are
      what every later visitor finds. On the public deployment,
      `DEMO_RESET_ON_BOOT=true` makes `priv/repo/seeds.exs` call
      `reset_activity!/0` and then `seed_activity!/1` on every boot, so
      each visitor after an idle spell starts from the same fresh,
      correctly dated demo.

  `ensure_accounts!/0` resets each demo account's password, role, and
  facility on every call. Every demo visitor shares these logins, so one
  of them can change a demo password from Settings or (as the MOH admin)
  reassign a role from `/admin/users`. Resetting on each boot undoes
  that. Render's free plan restarts the instance after it has been idle,
  so the reset happens often without needing a scheduled job.

  Seeding goes through each context's public API (`CaseManagement.create_case/1`,
  `LabReporting.record_result/3`, ...), the same way a real user's
  actions would, so broadcasts, lab-result side effects on case status,
  and validation all behave exactly as they do in normal use. The two
  places this module uses `Repo` directly are both seeding-only needs
  no context exposes on purpose: backdating a case's `inserted_at` (so
  the four-week risk trend has a shape), and setting a demo account's
  password/confirmation without going through the logged-in,
  sudo-mode-gated settings flow. `reset_activity!/0` is a third: no
  context offers a "delete everything" function, and none should.
  """

  import Ecto.Query, only: [from: 2]

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.Accounts.User
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.DrugAvailability.DrugStock
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.HospitalCapacity.CapacityReport
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.LabReporting.{LabCorrectionAcknowledgement, LabResultCorrection, LabTest}
  alias ZamHealthWatch.PublicAlerts.AlertSubscriber
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.VaccinationMonitoring
  alias ZamHealthWatch.VaccinationMonitoring.VaccinationRecord

  @password "zamhealthwatch-demo"

  @accounts [
    %{
      email: "health.worker@example.com",
      role: :health_worker,
      facility_code: "KBW",
      label: "Health worker",
      note: "Kabwata Clinic only - the Portal and facility-scoped reporting screens"
    },
    %{
      email: "district.officer@example.com",
      role: :district_officer,
      facility_code: nil,
      label: "District officer",
      note: "Every facility, plus the epidemiology, map, and risk dashboards"
    },
    %{
      email: "moh.admin@example.com",
      role: :moh_admin,
      facility_code: nil,
      label: "MOH admin",
      note: "Everything above, plus National Reporting and user management"
    },
    %{
      email: "lab.officer@example.com",
      role: :lab_officer,
      facility_code: nil,
      label: "Lab officer",
      note: "Enters lab results (Positive, Negative, Inconclusive) for every facility's tests"
    }
  ]

  # {facility code, disease, days ago}. Days are chosen to sit well
  # inside PredictiveAnalytics' 7-day buckets (never on day 7/14/21
  # exactly), so the weekly counts come out as intended:
  #
  #   * KBW: 1, 2, 3, 5 reports across the last four weeks. One week-2
  #     report is ruled out by a negative lab result (see
  #     seed_case_outcomes!/2), and ruled-out reports don't count, so
  #     the risk trend sees 1, 1, 3, 5 - still Elevated.
  #   * UTH: 2 cases every week - Stable.
  #   * NTH: 0, 0, 1, 1 measles - Stable. Ndola has no measles-rubella
  #     coverage record, so the district read shows "No coverage data".
  #   * MMH: 0, 0, 1, 1 measles - Stable for the facility - plus a
  #     malaria case six weeks ago, outside the window. Monze's
  #     measles-rubella coverage is 47.5% (@demo_coverage), so the
  #     district read raises Monze to High (Iteration 17).
  #
  # District read: Monze High, Lusaka Elevated (cholera; its 84% coverage
  # shows as a gap but changes nothing without measles cases), Ndola
  # Stable.
  #
  # The trend is relative to the moment of seeding, so it ages: four
  # weeks after a database is seeded, these cases fall out of the risk
  # window. With DEMO_RESET_ON_BOOT set, every boot reseeds from "now",
  # so the public demo never gets that old (see reset_activity!/0).
  @demo_cases [
    {"KBW", :cholera, 24},
    {"KBW", :cholera, 17},
    {"KBW", :cholera, 16},
    {"KBW", :cholera, 10},
    {"KBW", :cholera, 9},
    {"KBW", :typhoid, 8},
    {"KBW", :cholera, 4},
    {"KBW", :cholera, 3},
    {"KBW", :cholera, 2},
    {"KBW", :cholera, 1},
    {"KBW", :cholera, 0},
    {"UTH", :malaria, 25},
    {"UTH", :malaria, 22},
    {"UTH", :typhoid, 18},
    {"UTH", :malaria, 15},
    {"UTH", :covid19, 11},
    {"UTH", :malaria, 8},
    {"UTH", :malaria, 4},
    {"UTH", :malaria, 2},
    {"NTH", :measles, 12},
    {"NTH", :measles, 3},
    {"MMH", :measles, 12},
    {"MMH", :measles, 3},
    {"MMH", :malaria, 40}
  ]

  # Every table that holds demo *activity*, children before parents so
  # the `on_delete: :restrict` foreign keys are never violated. User
  # accounts and the reference districts and facilities aren't here:
  # those are reset or upserted by ensure_accounts!/0 and seeds.exs, not
  # wiped. Alert subscribers are, because on a public demo they're
  # visitors' phone numbers, which shouldn't outlive the demo session.
  @activity_schemas [
    LabCorrectionAcknowledgement,
    LabResultCorrection,
    LabTest,
    Case,
    DrugStock,
    CapacityReport,
    VaccinationRecord,
    AlertSubscriber
  ]

  # {facility code, medicine, quantity on hand, reorder level}
  @demo_stock [
    {"KBW", :ors, 40, 100},
    {"KBW", :iv_fluids, 15, 30},
    {"KBW", :al, 200, 100},
    {"UTH", :al, 500, 200},
    {"UTH", :ciprofloxacin, 80, 60},
    {"UTH", :ceftriaxone, 20, 50},
    {"NTH", :ors, 150, 100},
    {"MMH", :al, 30, 60}
  ]

  # {facility code, total beds, occupied, ICU total, ICU occupied, admissions today}
  @demo_capacity [
    {"KBW", 20, 19, 0, 0, 6},
    {"UTH", 600, 540, 40, 36, 45},
    {"NTH", 400, 250, 20, 8, 20},
    {"MMH", 120, 125, 4, 4, 9}
  ]

  # {district name, antigen, campaign, doses administered, target population}
  @demo_coverage [
    {"Lusaka", :measles_rubella, "Routine - 2026", 8400, 10_000},
    {"Lusaka", :opv, "Routine - 2026", 7100, 10_000},
    {"Ndola", :penta, "Routine - 2026", 5200, 6000},
    {"Monze", :measles_rubella, "Routine - 2026", 1900, 4000}
  ]

  @doc "The shared password for every demo account."
  def password, do: @password

  @doc """
  The demo accounts, for the home page to list and `ensure_accounts!/0`
  to create. Each is a map of `:email`, `:role`, `:facility_code` (or
  `nil`), `:label`, and `:note`.
  """
  def accounts, do: @accounts

  @doc """
  Creates any missing demo account, then resets every one to its
  published password, role, and facility - confirming it too, so
  password login works without the (unsendable) confirmation email.

  Raises if a demo account's facility doesn't exist yet - the reference
  facilities in `priv/repo/seeds.exs` have to be seeded first.
  """
  def ensure_accounts! do
    Enum.map(@accounts, &ensure_account!/1)
  end

  defp ensure_account!(%{email: email, role: role, facility_code: facility_code}) do
    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} = Accounts.register_user(%{email: email})
          user

        user ->
          user
      end

    user =
      user
      |> User.confirm_changeset()
      |> User.password_changeset(%{password: @password})
      |> Repo.update!()

    facility_id = facility_code && facility_id!(facility_code)
    {:ok, user} = Accounts.assign_user_role(user, %{role: role, facility_id: facility_id})
    user
  end

  @doc """
  Whether this deployment wipes and reseeds demo activity on every boot.

  Set by `DEMO_RESET_ON_BOOT=true` (read in `config/runtime.exs`). Off
  unless that's set, so a developer's database, or any deployment
  holding real data, is never wiped by accident.
  """
  def reset_on_boot?, do: Application.get_env(:zamhealthwatch, :demo_reset_on_boot, false) == true

  @doc """
  Deletes all demo activity: cases, lab tests and their corrections and
  acknowledgements, drug stock, capacity reports, vaccination records,
  alert subscribers, and alert jobs still waiting to run. Keeps user
  accounts, districts, and facilities.

  Destructive and unconditional - the caller decides whether to call
  it. `priv/repo/seeds.exs` only does so when `reset_on_boot?/0` is
  true, and follows it with `seed_activity!/1`, which then finds an
  empty database and seeds it afresh.

  Runs in one transaction, so a failure part-way leaves everything as
  it was. Returns the number of rows deleted, keyed by table name.
  """
  def reset_activity! do
    {:ok, deleted} =
      Repo.transact(fn ->
        # Jobs first: an alert job for a case that no longer exists
        # would fail on every one of its retries.
        {jobs, _} = Repo.delete_all(waiting_alert_jobs())

        tables =
          Enum.map(@activity_schemas, fn schema ->
            {count, _} = Repo.delete_all(schema)
            {schema.__schema__(:source), count}
          end)

        {:ok, Map.new([{"oban_jobs", jobs} | tables])}
      end)

    deleted
  end

  # Alert jobs that haven't run yet. Completed, discarded, and cancelled
  # ones are left for Oban's Pruner, and a job that's executing right
  # now is left to finish.
  defp waiting_alert_jobs do
    from j in Oban.Job,
      where: j.queue == "alerts" and j.state in ["available", "scheduled", "retryable"]
  end

  @doc """
  Seeds demo activity - cases, lab tests, drug stock, capacity reports,
  and vaccination coverage - but only into a database with no cases at
  all, so it never mixes into real data or duplicates itself on the
  next boot. Returns `:seeded` or `:skipped`.

  Needs the reference facilities/districts and the demo accounts
  (`ensure_accounts!/0`) to exist first. `now` is the reference point the
  cases are backdated from, overridable for tests.
  """
  def seed_activity!(now \\ DateTime.utc_now()) do
    if not CaseManagement.any_cases?() do
      seed_all!(now)
      :seeded
    else
      :skipped
    end
  end

  defp seed_all!(now) do
    worker = user!("health.worker@example.com")
    officer = user!("district.officer@example.com")
    lab_officer = user!("lab.officer@example.com")

    facility_ids =
      Map.new(~w(KBW UTH NTH MMH), fn code -> {code, facility_id!(code)} end)

    reporter_for = fn
      "KBW" -> worker.id
      _code -> officer.id
    end

    cases =
      for {code, disease, days_ago} <- @demo_cases do
        {:ok, case_record} =
          CaseManagement.create_case(%{
            disease: disease,
            facility_id: Map.fetch!(facility_ids, code),
            reported_by_id: reporter_for.(code)
          })

        backdate!(case_record, now, days_ago)
      end

    seed_case_outcomes!(cases, worker, lab_officer)

    for {code, medicine, qty, reorder} <- @demo_stock do
      {:ok, _stock} =
        DrugAvailability.record_stock(%{
          medicine: medicine,
          quantity_on_hand: qty,
          reorder_level: reorder,
          facility_id: Map.fetch!(facility_ids, code),
          reported_by_id: reporter_for.(code)
        })
    end

    for {code, total, occupied, icu_total, icu_occupied, admissions} <- @demo_capacity do
      {:ok, _report} =
        HospitalCapacity.record_capacity(%{
          total_beds: total,
          occupied_beds: occupied,
          icu_beds_total: icu_total,
          icu_beds_occupied: icu_occupied,
          admissions_today: admissions,
          facility_id: Map.fetch!(facility_ids, code),
          reported_by_id: reporter_for.(code)
        })
    end

    district_ids = Map.new(Geography.list_districts(), &{&1.name, &1.id})

    for {district, antigen, campaign, doses, target} <- @demo_coverage do
      {:ok, _record} =
        VaccinationMonitoring.record_vaccination(%{
          antigen: antigen,
          campaign: campaign,
          doses_administered: doses,
          target_population: target,
          district_id: Map.fetch!(district_ids, district),
          reported_by_id: officer.id
        })
    end

    :ok
  end

  # Lab tests on four of Kabwata's cholera cases - two positive (the
  # case moves to :confirmed), one still pending, and one first issued
  # as positive, then corrected to negative with a reason (the case
  # ends up :not_a_case, and /labs shows the correction history). All
  # through LabReporting itself, so the case-status effects are the
  # real ones. The oldest confirmed cholera patient died. At UTH, five
  # malaria cases are confirmed clinically and two of those patients
  # have recovered - so the case list and dashboards show every
  # classification and both outcomes.
  defp seed_case_outcomes!(cases, worker, lab_officer) do
    kabwata_cholera =
      Enum.filter(cases, &(&1.disease == :cholera and &1.reported_by_id == worker.id))

    {lab_cases, _rest} = Enum.split(kabwata_cholera, 4)

    lab_cases
    |> Enum.zip([:positive, :positive, :corrected_to_negative, :pending])
    |> Enum.each(fn {case_record, result} ->
      {:ok, lab_test} =
        LabReporting.request_test(%{case_id: case_record.id, requested_by_id: worker.id})

      case result do
        :pending ->
          :ok

        :corrected_to_negative ->
          {:ok, issued} = LabReporting.record_result(lab_test, :positive, lab_officer)

          {:ok, _corrected} =
            LabReporting.correct_result(
              issued,
              :negative,
              "Repeat test on a fresh sample was negative; the first sample was contaminated.",
              lab_officer
            )

        result ->
          {:ok, _resulted} = LabReporting.record_result(lab_test, result, lab_officer)
      end
    end)

    [first_lab_case | _] = lab_cases

    {:ok, _died} =
      first_lab_case.id
      |> CaseManagement.get_case!()
      |> CaseManagement.record_outcome(:died, :health_worker)

    uth_malaria =
      cases
      |> Enum.filter(&(&1.disease == :malaria and &1.reported_by_id != worker.id))
      |> Enum.take(5)

    confirmed =
      Enum.map(uth_malaria, fn case_record ->
        {:ok, updated} = CaseManagement.advance_case_status(case_record, :district_officer)
        updated
      end)

    confirmed
    |> Enum.take(2)
    |> Enum.each(fn case_record ->
      {:ok, _recovered} = CaseManagement.record_outcome(case_record, :recovered, :district_officer)
    end)
  end

  # Not something CaseManagement exposes on purpose - a real case's
  # report time is whenever it was actually reported. Seeding needs
  # cases spread over past weeks for the risk trend to have a shape.
  defp backdate!(case_record, now, days_ago) do
    timestamp =
      now
      |> DateTime.add(-days_ago * 86_400, :second)
      |> DateTime.truncate(:second)

    case_record
    |> Ecto.Changeset.change(inserted_at: timestamp, updated_at: timestamp)
    |> Repo.update!()
  end

  defp user!(email) do
    Accounts.get_user_by_email(email) ||
      raise "Demo account #{email} is missing - run ensure_accounts!/0 first"
  end

  defp facility_id!(code) do
    case Geography.get_facility_by_code(code) do
      nil -> raise "Demo facility #{code} is missing - seed the reference facilities first"
      facility -> facility.id
    end
  end
end
