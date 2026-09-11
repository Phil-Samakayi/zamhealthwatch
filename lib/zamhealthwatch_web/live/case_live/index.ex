defmodule ZamHealthWatchWeb.CaseLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography

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

      <.form for={@form} id="case-form" phx-submit="save" phx-change="validate">
        <.input
          field={@form[:disease]}
          type="select"
          label="Disease"
          options={@disease_options}
          prompt="Select a disease"
        />
        <.input
          field={@form[:facility_id]}
          type="select"
          label="Facility"
          options={@facility_options}
          prompt="Select a facility"
        />
        <.button variant="primary" phx-disable-with="Reporting...">Report case</.button>
      </.form>

      <div class="divider" />

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
        <:col :let={{_id, entry}} label="Reported">{time_ago(entry.inserted_at)}</:col>
        <:col :let={{_id, entry}} label="Actions">
          <.button
            :if={can_advance_status?(@current_scope, entry.status)}
            class="btn btn-xs"
            phx-click="advance_status"
            phx-value-id={entry.id}
          >
            {advance_label(entry.status)}
          </.button>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CaseManagement.subscribe_cases()

    facilities = Geography.list_facilities()
    cases = CaseManagement.list_cases()

    socket =
      socket
      |> assign(:disease_options, Case.disease_options())
      |> assign(:facility_options, Enum.map(facilities, &{&1.name, &1.id}))
      |> assign(:facilities_by_id, Map.new(facilities, &{&1.id, &1.name}))
      |> assign(:reporters_by_id, Map.new(Accounts.list_users(), &{&1.id, reporter_label(&1)}))
      |> assign(:case_count, length(cases))
      |> assign_form(CaseManagement.change_case(%Case{}))
      |> stream(:cases, cases)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"case" => case_params}, socket) do
    changeset =
      %Case{}
      |> CaseManagement.change_case(with_reporter(case_params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"case" => case_params}, socket) do
    case CaseManagement.create_case(with_reporter(case_params, socket)) do
      {:ok, _case} ->
        {:noreply,
         socket
         |> put_flash(:info, "Case reported.")
         |> assign_form(CaseManagement.change_case(%Case{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
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

  @impl true
  def handle_info({:created, %Case{} = case_record}, socket) do
    {:noreply,
     socket
     |> stream_insert(:cases, case_record, at: 0)
     |> update(:case_count, &(&1 + 1))}
  end

  def handle_info({:updated, %Case{} = case_record}, socket) do
    {:noreply, stream_insert(socket, :cases, case_record)}
  end

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
  defp status_badge_class(:resolved), do: "badge-success"

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

  defp advance_label(:suspected), do: "Confirm"
  defp advance_label(:confirmed), do: "Resolve"

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
