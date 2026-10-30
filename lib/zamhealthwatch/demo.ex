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
  sudo-mode-gated settings flow.
  """

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.Accounts.User
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.DrugAvailability
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.HospitalCapacity
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.Repo
  alias ZamHealthWatch.VaccinationMonitoring

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
  #   * NTH: 0, 0, 1, 1 - Stable.
  #   * MMH: one case six weeks ago, outside the window - No data.
  #
  # The trend is relative to the moment of seeding, so it ages: four
  # weeks after a fresh database is seeded, these cases fall out of the
  # risk window. Logged in docs/ITERATIONS.md as a known limitation.
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
    {"MMH", :malaria, 40}
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

    seed_case_outcomes!(cases, worker)

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
  # case moves to :confirmed), one negative (:not_a_case), one still
  # pending - via LabReporting.record_result/3 itself, so the case-status
  # side effect is the real one. The oldest confirmed cholera patient
  # died. At UTH, five malaria cases are confirmed clinically and two of
  # those patients have recovered - so the case list and dashboards show
  # every classification and both outcomes.
  defp seed_case_outcomes!(cases, worker) do
    kabwata_cholera =
      Enum.filter(cases, &(&1.disease == :cholera and &1.reported_by_id == worker.id))

    {lab_cases, _rest} = Enum.split(kabwata_cholera, 4)

    lab_cases
    |> Enum.zip([:positive, :positive, :negative, :pending])
    |> Enum.each(fn {case_record, result} ->
      {:ok, lab_test} =
        LabReporting.request_test(%{case_id: case_record.id, requested_by_id: worker.id})

      if result != :pending do
        {:ok, _resulted} = LabReporting.record_result(lab_test, result, :health_worker)
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
        {:ok, updated} = CaseManagement.update_case_status(case_record, %{status: :confirmed})
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
