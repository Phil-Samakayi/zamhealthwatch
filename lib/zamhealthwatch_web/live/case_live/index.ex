defmodule ZamHealthWatchWeb.CaseLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.CaseManagement.OutcomeCorrection
  alias ZamHealthWatch.Geography

  # Since Iteration 15, closing a case means recording what happened to
  # the patient, not moving it to a "resolved" classification - see
  # Case's `outcome` field.
  @outcome_options [{"Recovered", :recovered}, {"Died", :died}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Report a case
        <:subtitle>
          Reports are persisted immediately and broadcast live to everyone watching the list below.
        </:subtitle>
      </.header>

      <div :if={@scope == :unassigned} class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          You haven't been assigned to a facility yet. Ask an MOH admin to assign you from
          <.link navigate={~p"/admin/users"} class="link">Manage users</.link>.
        </span>
      </div>

      <.form
        :if={@scope != :unassigned}
        for={@form}
        id="case-form"
        phx-submit="save"
        phx-change="validate"
      >
        <.input
          field={@form[:disease]}
          type="select"
          label="Disease"
          options={@disease_options}
          prompt="Select a disease"
        />
        <.input
          :if={@locked_facility}
          type="text"
          name="case[facility_display]"
          label="Facility"
          value={@locked_facility.name}
          disabled
        />
        <.input
          :if={!@locked_facility}
          field={@form[:facility_id]}
          type="select"
          label="Facility"
          options={@facility_options}
          prompt="Select a facility"
        />
        <.button variant="primary" phx-disable-with="Reporting...">Report case</.button>
      </.form>

      <div class="divider" />

      <div
        :if={@outcome_panel}
        id="outcome-panel"
        class="rounded-box border border-base-300 bg-base-200 p-4 space-y-3"
      >
        <h3 class="font-semibold">Outcome</h3>
        <p class="text-sm">
          {Case.disease_label(@outcome_panel.case.disease)} case at {Map.get(
            @facilities_by_id,
            @outcome_panel.case.facility_id,
            "Unknown facility"
          )}. Current outcome:
          <span class="font-semibold">{outcome_label(@outcome_panel.case.outcome)}</span>.
          <span :if={@outcome_panel.case.outcome_recorded_by_id}>
            Recorded by {Map.get(@reporters_by_id, @outcome_panel.case.outcome_recorded_by_id, "Unknown user")}.
          </span>
        </p>

        <.form
          :if={@outcome_panel.can_correct}
          for={@outcome_form}
          id="outcome-correction-form"
          phx-submit="submit_outcome_correction"
        >
          <input type="hidden" name="correction[case_id]" value={@outcome_panel.case.id} />
          <.input
            field={@outcome_form[:change_to]}
            type="select"
            label="Change to"
            options={change_to_options(@outcome_panel.case.outcome)}
            prompt="Select a correction"
          />
          <p class="text-xs text-base-content/60">
            Remove the outcome only if it should never have been recorded on this case (entered on the wrong patient's case, for example). An outcome that was simply wrong should be changed.
          </p>
          <.input
            field={@outcome_form[:reason]}
            type="textarea"
            label="Reason (required, at least 10 characters)"
          />
          <.button variant="primary" phx-disable-with="Saving...">Save correction</.button>
        </.form>

        <div :if={@outcome_panel.history != []} id="outcome-history">
          <h4 class="font-semibold text-sm">
            Correction history
            <span class="font-normal text-base-content/60">
              - newest first. Nothing here is ever edited or deleted.
            </span>
          </h4>
          <.table
            id="outcome-corrections"
            rows={@outcome_panel.history}
            row_id={&"outcome-correction-#{&1.id}"}
          >
            <:col :let={correction} label="When">{time_ago(correction.inserted_at)}</:col>
            <:col :let={correction} label="Change">{outcome_change_label(correction)}</:col>
            <:col :let={correction} label="Reason">{correction.reason}</:col>
            <:col :let={correction} label="By">
              {Map.get(@reporters_by_id, correction.corrected_by_id, "Unknown user")}
            </:col>
          </.table>
        </div>

        <button type="button" class="btn btn-sm" phx-click="close_outcome_panel">Close</button>
      </div>

      <.header>
        Reported cases
        <:subtitle>
          {@case_count} case{if @case_count != 1, do: "s"} reported so far.
        </:subtitle>
      </.header>

      <p :if={@case_count == 0} id="no-cases" class="text-sm text-base-content/60">
        No cases reported yet — reported cases will appear here in real time.
      </p>

      <.table :if={@case_count > 0} id="cases" rows={@streams.cases}>
        <:col :let={{_id, entry}} label="Disease">{Case.disease_label(entry.disease)}</:col>
        <:col :let={{_id, entry}} label="Facility">
          {Map.get(@facilities_by_id, entry.facility_id, "Unknown facility")}
        </:col>
        <:col :let={{_id, entry}} label="Reported by">
          {Map.get(@reporters_by_id, entry.reported_by_id, "Unknown reporter")}
        </:col>
        <:col :let={{_id, entry}} label="Status">
          <span class={["badge", status_badge_class(entry.status)]}>
            {Phoenix.Naming.humanize(entry.status)}
          </span>
        </:col>
        <:col :let={{_id, entry}} label="Outcome">
          <span :if={entry.outcome} class={["badge", outcome_badge_class(entry.outcome)]}>
            {Phoenix.Naming.humanize(entry.outcome)}
          </span>
          <button
            :if={MapSet.member?(@corrected_case_ids, entry.id)}
            type="button"
            class="badge badge-outline badge-sm cursor-pointer"
            phx-click="open_outcome_panel"
            phx-value-id={entry.id}
          >
            Corrected
          </button>
        </:col>
        <:col :let={{_id, entry}} label="Reported">{time_ago(entry.inserted_at)}</:col>
        <:col :let={{_id, entry}} label="Actions">
          <div class="flex flex-wrap gap-1">
            <.button
              :if={can_advance_status?(@current_scope, entry.status)}
              class="btn btn-xs"
              phx-click="advance_status"
              phx-value-id={entry.id}
            >
              Confirm
            </.button>
            <.button
              :for={{label, outcome} <- @outcome_options}
              :if={can_record_outcome?(@current_scope, entry)}
              class="btn btn-xs"
              phx-click="record_outcome"
              phx-value-id={entry.id}
              phx-value-outcome={outcome}
            >
              {label}
            </.button>
            <.button
              :if={can_correct_outcome?(@current_scope, entry)}
              class="btn btn-xs"
              phx-click="open_outcome_panel"
              phx-value-id={entry.id}
            >
              Correct outcome
            </.button>
          </div>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CaseManagement.subscribe_cases()

    scope = facility_scope(socket.assigns.current_scope.user)
    facilities = Geography.list_facilities()
    cases = list_cases(scope)

    socket =
      socket
      |> assign(:scope, scope)
      |> assign(:locked_facility, locked_facility(scope))
      |> assign(:disease_options, Case.disease_options())
      |> assign(:outcome_options, @outcome_options)
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1.name}))
      |> assign(:reporters_by_id, Map.new(Accounts.list_users(), &{&1.id, reporter_label(&1)}))
      |> assign(:case_count, length(cases))
      |> assign(:corrected_case_ids, CaseManagement.list_outcome_corrected_case_ids())
      |> assign(:outcome_panel, nil)
      |> assign(:outcome_form, empty_outcome_form())
      |> assign_form(CaseManagement.change_case(%Case{}))
      |> stream(:cases, cases)

    {:ok, socket}
  end

  # A health_worker only ever sees/reports cases at their own facility;
  # every other role (including an unassigned nil role) is unrestricted
  # on this screen - see docs/ITERATIONS.md's Health Worker Portal
  # facility-scoping decision. `:unassigned` is a health_worker with no
  # `facility_id` yet (nothing to scope to), distinct from
  # `:unrestricted` so the empty state matches PortalLive.Index's own
  # "get assigned" message rather than silently falling back to
  # showing everything. Same shape duplicated (not shared) across
  # DrugLive.Index/HospitalLive.Index/LabLive.Index/VaccinationLive.Index,
  # same small-per-module-helper convention `with_reporter/2` already set.
  defp facility_scope(%{role: :health_worker, facility_id: nil}), do: :unassigned
  defp facility_scope(%{role: :health_worker, facility_id: facility_id}), do: {:locked, facility_id}
  defp facility_scope(_user), do: :unrestricted

  defp list_cases(:unrestricted), do: CaseManagement.list_cases()
  defp list_cases(:unassigned), do: []
  defp list_cases({:locked, facility_id}), do: CaseManagement.list_cases_by_facility(facility_id)

  # Same "don't let a display-only lookup crash the page" fallback
  # PortalLive.Index's own fetch_facility/1 already applies.
  defp locked_facility({:locked, facility_id}) do
    Geography.get_facility!(facility_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp locked_facility(_scope), do: nil

  # Forces `facility_id` to the health worker's own facility regardless
  # of what the client submits - same server-side-enforcement precedent
  # `with_reporter/2` already set for `reported_by_id`, applied here
  # because a locked facility is a real authorization boundary (the
  # user's own choice to lock the case-report form, not just filter its
  # list), not only a UI nicety.
  defp apply_scope(case_params, {:locked, facility_id}),
    do: Map.put(case_params, "facility_id", facility_id)

  defp apply_scope(case_params, _scope), do: case_params

  defp scoped_params(case_params, socket) do
    case_params |> with_reporter(socket) |> apply_scope(socket.assigns.scope)
  end

  @impl true
  def handle_event("validate", %{"case" => case_params}, socket) do
    changeset =
      %Case{}
      |> CaseManagement.change_case(scoped_params(case_params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"case" => case_params}, socket) do
    case socket.assigns.scope do
      :unassigned ->
        {:noreply,
         put_flash(socket, :error, "You need to be assigned to a facility before reporting a case.")}

      _scope ->
        case CaseManagement.create_case(scoped_params(case_params, socket)) do
          {:ok, _case} ->
            {:noreply,
             socket
             |> put_flash(:info, "Case reported.")
             |> assign_form(CaseManagement.change_case(%Case{}))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end
    end
  end

  # `role` is read from `current_scope`, not trusted from client params -
  # there's no form field to tamper with here, but the event handler
  # below re-checks the same thing server-side anyway (CaseManagement.
  # advance_case_status/2's own job), the same "don't trust the button
  # being hidden" precedent with_reporter/2 already set for reported_by_id.
  def handle_event("advance_status", %{"id" => id}, socket) do
    case_record = CaseManagement.get_case!(id)
    role = socket.assigns.current_scope.user.role

    case CaseManagement.advance_case_status(case_record, role) do
      {:ok, updated_case} ->
        # No manual stream_insert here - the broadcast update_case_status/2
        # already sent lands right back on this same LiveView's
        # handle_info({:updated, _}, _) below, same "rely on the PubSub
        # round-trip" pattern handle_event("save", ...) already uses for
        # newly-created cases.
        {:noreply,
         put_flash(socket, :info, "Case moved to #{Phoenix.Naming.humanize(updated_case.status)}.")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, "You need an assigned role to change a case's status.")}

      {:error, :no_next_status} ->
        {:noreply, put_flash(socket, :error, "This case has no further status to move to.")}
    end
  end

  # Same server-side re-check shape as "advance_status" above -
  # CaseManagement.record_outcome/3 enforces role, classification, and
  # "not already recorded" itself. `outcome` goes through to_outcome/1
  # rather than String.to_existing_atom/1 directly, so a forged value
  # gets a clean error instead of crashing the LiveView - same reasoning
  # as LabLive.Index's to_result/1.
  def handle_event("record_outcome", %{"id" => id, "outcome" => outcome}, socket) do
    case_record = CaseManagement.get_case!(id)
    recorder = socket.assigns.current_scope.user

    with outcome when not is_nil(outcome) <- to_outcome(outcome),
         {:ok, updated_case} <- CaseManagement.record_outcome(case_record, outcome, recorder) do
      {:noreply,
       put_flash(
         socket,
         :info,
         "Outcome recorded: #{Phoenix.Naming.humanize(updated_case.outcome)}."
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Unrecognized outcome.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You need an assigned role to record an outcome.")}

      {:error, :not_a_case} ->
        {:noreply,
         put_flash(socket, :error, "This case was ruled out, so there's no outcome to record.")}

      {:error, :outcome_already_recorded} ->
        {:noreply, put_flash(socket, :error, "This case already has a recorded outcome.")}
    end
  end

  # Opens the outcome panel: the case's outcome, its correction history,
  # and - for a role that can correct outcomes, on a case that has one -
  # the correction form. Anyone who can see the case can see its
  # history; a forged id for a case outside a health worker's facility
  # is refused.
  def handle_event("open_outcome_panel", %{"id" => id}, socket) do
    case_record = CaseManagement.get_case!(id)

    if in_scope?(socket.assigns.scope, case_record) do
      {:noreply,
       socket
       |> assign(:outcome_panel, outcome_panel(case_record, socket.assigns.current_scope))
       |> assign(:outcome_form, empty_outcome_form())}
    else
      {:noreply, put_flash(socket, :error, "That case isn't at your facility.")}
    end
  end

  def handle_event("close_outcome_panel", _params, socket) do
    {:noreply, assign(socket, :outcome_panel, nil)}
  end

  # CaseManagement re-checks the role, the outcome, and the reason
  # itself; the form being visible is not the authorization boundary.
  def handle_event("submit_outcome_correction", %{"correction" => params}, socket) do
    case_record = CaseManagement.get_case!(params["case_id"])
    corrector = socket.assigns.current_scope.user
    reason = Map.get(params, "reason", "")

    result =
      case Map.get(params, "change_to") do
        "entered_in_error" ->
          CaseManagement.withdraw_outcome(case_record, reason, corrector)

        change_to ->
          case to_outcome(change_to) do
            nil -> {:error, :no_change_selected}
            outcome -> CaseManagement.correct_outcome(case_record, outcome, reason, corrector)
          end
      end

    case result do
      {:ok, %Case{outcome: nil}} ->
        {:noreply,
         socket
         |> assign(:outcome_panel, nil)
         |> put_flash(:info, "Outcome removed as entered in error.")}

      {:ok, updated_case} ->
        {:noreply,
         socket
         |> assign(:outcome_panel, nil)
         |> put_flash(:info, "Outcome corrected to #{outcome_label(updated_case.outcome)}.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> assign(
           :outcome_form,
           to_form(Map.take(params, ["change_to", "reason"]), as: "correction")
         )
         |> put_flash(:error, "Give a reason of at least 10 characters.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, outcome_correction_error(error))}
    end
  end

  # Only cases this user can see are added or updated: before Iteration
  # 18 every broadcast case was streamed in, so a health worker's list
  # picked up live reports from other facilities until they reloaded.
  @impl true
  def handle_info({:created, %Case{} = case_record}, socket) do
    if in_scope?(socket.assigns.scope, case_record) do
      {:noreply,
       socket
       |> stream_insert(:cases, case_record, at: 0)
       |> update(:case_count, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # The corrected-case set is refreshed before the row is re-inserted,
  # so the row renders with its "Corrected" marker. An open panel on the
  # same case is refreshed too, so its history and form stay current.
  def handle_info({:updated, %Case{} = case_record}, socket) do
    if in_scope?(socket.assigns.scope, case_record) do
      {:noreply,
       socket
       |> assign(:corrected_case_ids, CaseManagement.list_outcome_corrected_case_ids())
       |> refresh_outcome_panel(case_record)
       |> stream_insert(:cases, case_record)}
    else
      {:noreply, socket}
    end
  end

  defp in_scope?(:unrestricted, _case_record), do: true
  defp in_scope?({:locked, facility_id}, %Case{facility_id: facility_id}), do: true
  defp in_scope?(_scope, _case_record), do: false

  defp outcome_panel(case_record, current_scope) do
    %{
      case: case_record,
      history: CaseManagement.list_outcome_corrections_for_case(case_record.id),
      can_correct: can_correct_outcome?(current_scope, case_record)
    }
  end

  defp refresh_outcome_panel(
         %{assigns: %{outcome_panel: %{case: %{id: id}}}} = socket,
         %Case{id: id} = case_record
       ) do
    assign(socket, :outcome_panel, outcome_panel(case_record, socket.assigns.current_scope))
  end

  defp refresh_outcome_panel(socket, _case_record), do: socket

  defp empty_outcome_form do
    to_form(%{"change_to" => nil, "reason" => ""}, as: "correction")
  end

  # Every outcome other than the current one, plus removing it.
  defp change_to_options(current_outcome) do
    Enum.reject(@outcome_options, fn {_label, value} -> value == current_outcome end) ++
      [{"Remove - entered in error", "entered_in_error"}]
  end

  defp outcome_label(nil), do: "none recorded"
  defp outcome_label(outcome), do: Phoenix.Naming.humanize(outcome)

  defp outcome_change_label(%OutcomeCorrection{kind: :entered_in_error} = correction),
    do: "#{outcome_label(correction.previous_outcome)} → removed (entered in error)"

  defp outcome_change_label(%OutcomeCorrection{} = correction),
    do: "#{outcome_label(correction.previous_outcome)} → #{outcome_label(correction.new_outcome)}"

  defp outcome_correction_error(:unauthorized),
    do: "Only a district officer or MOH admin can correct an outcome."

  defp outcome_correction_error(:no_outcome), do: "This case has no recorded outcome to correct."
  defp outcome_correction_error(:unchanged), do: "That's already this case's outcome."
  defp outcome_correction_error(:no_change_selected), do: "Choose what to change the outcome to."
  defp outcome_correction_error(_error), do: "That correction couldn't be saved."

  # `reported_by_id` is never taken from client params - it isn't a field on
  # the form - it's always the currently authenticated user, set here before
  # the params ever reach the context. Every authenticated user can report a
  # case today (see CaseManagement's Iteration 1 decision log); this is only
  # about *who* gets recorded as the reporter, not an authorization check.
  defp with_reporter(case_params, socket) do
    Map.put(case_params, "reported_by_id", socket.assigns.current_scope.user.id)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "case"))
  end

  defp status_badge_class(:suspected), do: "badge-warning"
  defp status_badge_class(:confirmed), do: "badge-error"
  defp status_badge_class(:not_a_case), do: "badge-ghost"

  defp outcome_badge_class(:recovered), do: "badge-success"
  defp outcome_badge_class(:died), do: "badge-neutral"

  defp to_outcome(outcome) when outcome in ~w(recovered died), do: String.to_existing_atom(outcome)
  defp to_outcome(_outcome), do: nil

  # Email for a web-registered reporter, phone for an SMS-only one
  # (Iteration 2's SmsReporting slice made `email` nullable and gave an
  # SMS reporter only a `phone` - see `Accounts.find_or_create_sms_reporter/1`).
  # Falls back the same way `Map.get(@facilities_by_id, ..., "Unknown facility")`
  # already does for a dangling reference, even though `reported_by_id` is a
  # required, `on_delete: :restrict` FK (Iteration 1's audit-trail decision)
  # and so should never actually be missing from `@reporters_by_id`.
  defp reporter_label(%{email: email}) when is_binary(email), do: email
  defp reporter_label(%{phone: phone}) when is_binary(phone), do: phone
  defp reporter_label(_user), do: "Unknown reporter"

  # Mirrors CaseManagement.advance_case_status/2's own checks - shown
  # here purely to decide whether to render the button at all. The
  # context re-checks both the same way regardless, since hiding a
  # button is a UI nicety, not an authorization boundary on its own.
  defp can_advance_status?(current_scope, status) do
    not is_nil(current_scope.user.role) and not is_nil(CaseManagement.next_status(status))
  end

  # Mirrors CaseManagement.record_outcome/3's checks, for the same
  # "hiding a button isn't the authorization boundary" reason.
  defp can_record_outcome?(current_scope, %Case{status: status, outcome: outcome}) do
    not is_nil(current_scope.user.role) and status != :not_a_case and is_nil(outcome)
  end

  # Mirrors CaseManagement.correct_outcome/4's checks, for the same reason.
  defp can_correct_outcome?(current_scope, %Case{outcome: outcome}) do
    CaseManagement.can_correct_outcomes?(current_scope.user.role) and not is_nil(outcome)
  end

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
