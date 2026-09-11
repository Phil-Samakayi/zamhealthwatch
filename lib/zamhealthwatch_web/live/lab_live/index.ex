defmodule ZamHealthWatchWeb.LabLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.LabReporting.LabTest

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Request a lab test
        <:subtitle>
          Link a lab test to an existing case. A positive result confirms the case;
          negative resolves it (ruled out); inconclusive leaves it unchanged.
        </:subtitle>
      </.header>

      <.form for={@form} id="lab-test-form" phx-submit="save">
        <.input
          field={@form[:case_id]}
          type="select"
          label="Case"
          options={@case_options}
          prompt="Select a case"
        />
        <.button variant="primary" phx-disable-with="Requesting...">Request test</.button>
      </.form>

      <div class="divider" />

      <.header>
        Lab tests
        <:subtitle>
          {@lab_test_count} test{if @lab_test_count != 1, do: "s"} requested so far.
        </:subtitle>
      </.header>

      <p :if={@lab_test_count == 0} id="no-lab-tests" class="text-sm text-base-content/60">
        No lab tests requested yet.
      </p>

      <.table :if={@lab_test_count > 0} id="lab-tests" rows={@streams.lab_tests}>
        <:col :let={{_id, entry}} label="Case">
          {case_label(entry, @cases_by_id, @facilities_by_id)}
        </:col>
        <:col :let={{_id, entry}} label="Status">
          <span class={["badge", status_badge_class(entry.status)]}>
            {Phoenix.Naming.humanize(entry.status)}
          </span>
        </:col>
        <:col :let={{_id, entry}} label="Result">
          {entry.result && Phoenix.Naming.humanize(entry.result)}
        </:col>
        <:col :let={{_id, entry}} label="Requested">{time_ago(entry.inserted_at)}</:col>
        <:col :let={{_id, entry}} label="Actions">
          <div :if={can_record_result?(@current_scope, entry)} class="flex gap-1">
            <.button
              class="btn btn-xs"
              phx-click="record_result"
              phx-value-id={entry.id}
              phx-value-result="positive"
            >
              Positive
            </.button>
            <.button
              class="btn btn-xs"
              phx-click="record_result"
              phx-value-id={entry.id}
              phx-value-result="negative"
            >
              Negative
            </.button>
            <.button
              class="btn btn-xs"
              phx-click="record_result"
              phx-value-id={entry.id}
              phx-value-result="inconclusive"
            >
              Inconclusive
            </.button>
          </div>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: LabReporting.subscribe_lab_tests()

    cases = CaseManagement.list_cases()
    facilities = Geography.list_facilities()
    facilities_by_id = Map.new(facilities, &{&1.id, &1.name})
    lab_tests = LabReporting.list_lab_tests()

    socket =
      socket
      |> assign(:cases_by_id, Map.new(cases, &{&1.id, &1}))
      |> assign(:facilities_by_id, facilities_by_id)
      |> assign(:case_options, Enum.map(cases, &{case_option_label(&1, facilities_by_id), &1.id}))
      |> assign(:lab_test_count, length(lab_tests))
      |> assign_form(LabReporting.change_lab_test(%LabTest{}))
      |> stream(:lab_tests, lab_tests)

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"lab_test" => params}, socket) do
    case LabReporting.request_test(with_requester(params, socket)) do
      {:ok, _lab_test} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lab test requested.")
         |> assign_form(LabReporting.change_lab_test(%LabTest{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # `role` is read from `current_scope`, not trusted from client params -
  # same "hiding the buttons is a UI nicety, the context re-checks
  # regardless" precedent CaseLive.Index's own "advance_status" handler
  # already established for `advance_case_status/2`. `result` is parsed
  # through `to_result/1` rather than `String.to_existing_atom/1`
  # directly, so a forged event with an unrecognized value returns a
  # clean error instead of crashing the LiveView.
  def handle_event("record_result", %{"id" => id, "result" => result}, socket) do
    lab_test = LabReporting.get_lab_test!(id)
    role = socket.assigns.current_scope.user.role

    case to_result(result) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unrecognized result value.")}

      result_atom ->
        case LabReporting.record_result(lab_test, result_atom, role) do
          {:ok, updated} ->
            # No manual stream_insert here - same "rely on the PubSub
            # round-trip" pattern CaseLive.Index's own handle_event("save",
            # ...)/"advance_status" already use: record_result/3's own
            # broadcast lands right back on this LiveView's handle_info
            # below.
            {:noreply,
             put_flash(
               socket,
               :info,
               "Result recorded: #{Phoenix.Naming.humanize(updated.result)}."
             )}

          {:error, :unauthorized} ->
            {:noreply,
             put_flash(socket, :error, "You need an assigned role to record a lab result.")}

          {:error, :already_resulted} ->
            {:noreply, put_flash(socket, :error, "This test already has a recorded result.")}
        end
    end
  end

  @impl true
  def handle_info({:created, %LabTest{} = lab_test}, socket) do
    {:noreply,
     socket
     |> stream_insert(:lab_tests, lab_test, at: 0)
     |> update(:lab_test_count, &(&1 + 1))}
  end

  def handle_info({:updated, %LabTest{} = lab_test}, socket) do
    {:noreply, stream_insert(socket, :lab_tests, lab_test)}
  end

  defp to_result(result) when result in ~w(positive negative inconclusive) do
    String.to_existing_atom(result)
  end

  defp to_result(_result), do: nil

  # `requested_by_id` is never taken from client params - same
  # "server sets it from current_scope, not the form" pattern
  # CaseLive.Index's `with_reporter/2` already established for
  # `reported_by_id`.
  defp with_requester(params, socket) do
    Map.put(params, "requested_by_id", socket.assigns.current_scope.user.id)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "lab_test"))
  end

  defp case_option_label(case_record, facilities_by_id) do
    facility_name = Map.get(facilities_by_id, case_record.facility_id, "Unknown facility")

    "#{Case.disease_label(case_record.disease)} - #{facility_name} " <>
      "(#{Phoenix.Naming.humanize(case_record.status)})"
  end

  defp case_label(%LabTest{case_id: case_id}, cases_by_id, facilities_by_id) do
    case Map.get(cases_by_id, case_id) do
      nil ->
        "Unknown case"

      case_record ->
        facility_name = Map.get(facilities_by_id, case_record.facility_id, "Unknown facility")
        "#{Case.disease_label(case_record.disease)} - #{facility_name}"
    end
  end

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:resulted), do: "badge-success"

  # Mirrors LabReporting.record_result/3's own checks - shown here
  # purely to decide whether to render the buttons at all. The context
  # re-checks both the same way regardless, since hiding a button is a
  # UI nicety, not an authorization boundary on its own (same precedent
  # CaseLive.Index.can_advance_status?/2 already set).
  defp can_record_result?(current_scope, %LabTest{status: :pending}) do
    not is_nil(current_scope.user.role)
  end

  defp can_record_result?(_current_scope, _lab_test), do: false
end
