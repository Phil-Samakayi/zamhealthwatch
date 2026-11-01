defmodule ZamHealthWatchWeb.LabLive.Index do
  use ZamHealthWatchWeb, :live_view

  import ZamHealthWatchWeb.TimeHelpers, only: [time_ago: 1]

  alias ZamHealthWatch.Accounts
  alias ZamHealthWatch.CaseManagement
  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Geography
  alias ZamHealthWatch.LabReporting
  alias ZamHealthWatch.LabReporting.LabResultCorrection
  alias ZamHealthWatch.LabReporting.LabTest

  @result_options [{"Positive", :positive}, {"Negative", :negative}, {"Inconclusive", :inconclusive}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Request a lab test
        <:subtitle>
          Link a lab test to an existing case. Results are entered by lab officers: a
          positive result confirms the case, negative rules it out, and inconclusive leaves
          it unchanged. An issued result is never edited in place - it's corrected or
          withdrawn with a reason, and the history below keeps the original.
        </:subtitle>
      </.header>

      <div
        :if={@correction_notices != []}
        id="correction-notices"
        class="alert alert-warning flex-col items-start"
      >
        <p class="font-semibold">
          {if length(@correction_notices) == 1,
            do: "A result on a test you requested has been corrected",
            else: "Results on tests you requested have been corrected"}
        </p>
        <ul class="w-full space-y-1">
          <li
            :for={notice <- @correction_notices}
            id={"notice-#{notice.id}"}
            class="flex flex-wrap items-center justify-between gap-2"
          >
            <span>
              {correction_case_label(notice, @lab_tests_by_id, @cases_by_id, @facilities_by_id)}:
              <span class="font-semibold">{change_label(notice)}</span> - {notice.reason}
            </span>
            <.button class="btn btn-xs" phx-click="acknowledge_correction" phx-value-id={notice.id}>
              Mark as seen
            </.button>
          </li>
        </ul>
      </div>

      <div :if={@scope == :unassigned} class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <span>
          You haven't been assigned to a facility yet. Ask an MOH admin to assign you from
          <.link navigate={~p"/admin/users"} class="link">Manage users</.link>.
        </span>
      </div>

      <.form :if={@scope != :unassigned} for={@form} id="lab-test-form" phx-submit="save">
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

      <div
        :if={@correcting}
        id="correction-panel"
        class="rounded-box border border-base-300 bg-base-200 p-4 space-y-2"
      >
        <h3 class="font-semibold">
          {if @correcting.mode == :correct, do: "Correct a result", else: "Withdraw a result"}
        </h3>
        <p class="text-sm">
          {case_label(@correcting.lab_test, @cases_by_id, @facilities_by_id)} - currently
          <span class="font-semibold">{result_label(@correcting.lab_test.result)}</span>.
          <span :if={@correcting.mode == :withdraw}>
            Withdraw only a result that should never have been recorded against this test (entered
            on the wrong case, for example). A result that was simply wrong should be corrected.
          </span>
        </p>

        <.form for={@correction_form} id="correction-form" phx-submit="submit_correction">
          <input type="hidden" name="correction[lab_test_id]" value={@correcting.lab_test.id} />
          <input type="hidden" name="correction[mode]" value={@correcting.mode} />
          <.input
            :if={@correcting.mode == :correct}
            field={@correction_form[:new_result]}
            type="select"
            label="Corrected result"
            options={Enum.reject(@result_options, fn {_label, value} -> value == @correcting.lab_test.result end)}
            prompt="Select the correct result"
          />
          <.input
            field={@correction_form[:reason]}
            type="textarea"
            label="Reason (required, at least 10 characters)"
          />
          <div class="flex gap-2">
            <.button variant="primary" phx-disable-with="Saving...">
              {if @correcting.mode == :correct, do: "Save correction", else: "Withdraw result"}
            </.button>
            <button type="button" class="btn" phx-click="cancel_correction">Cancel</button>
          </div>
        </.form>
      </div>

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
            {status_label(entry.status)}
          </span>
        </:col>
        <:col :let={{_id, entry}} label="Result">
          <span class={entry.status == :entered_in_error && "line-through text-base-content/50"}>
            {result_label(entry.result)}
          </span>
        </:col>
        <:col :let={{_id, entry}} label="Resulted by">{resulted_by_label(entry, @users_by_id)}</:col>
        <:col :let={{_id, entry}} label="Requested">{time_ago(entry.inserted_at)}</:col>
        <:col :let={{_id, entry}} label="Actions">
          <div :if={can_record_result?(@current_scope, entry)} class="flex gap-1">
            <.button
              :for={{label, value} <- @result_options}
              class="btn btn-xs"
              phx-click="record_result"
              phx-value-id={entry.id}
              phx-value-result={value}
            >
              {label}
            </.button>
          </div>
          <div :if={can_correct?(@current_scope, entry)} class="flex gap-1">
            <.button
              class="btn btn-xs"
              phx-click="start_correction"
              phx-value-id={entry.id}
              phx-value-mode="correct"
            >
              Correct
            </.button>
            <.button
              class="btn btn-xs"
              phx-click="start_correction"
              phx-value-id={entry.id}
              phx-value-mode="withdraw"
            >
              Withdraw
            </.button>
          </div>
        </:col>
      </.table>

      <div :if={@corrections != []} id="correction-history">
        <div class="divider" />

        <.header>
          Correction history
          <:subtitle>
            Every correction and withdrawal, newest first. Nothing here is ever edited or
            deleted - the first entry for a test shows the result as originally issued.
          </:subtitle>
        </.header>

        <.table id="corrections" rows={@corrections} row_id={&"correction-#{&1.id}"}>
          <:col :let={correction} label="When">{time_ago(correction.inserted_at)}</:col>
          <:col :let={correction} label="Case">
            {correction_case_label(correction, @lab_tests_by_id, @cases_by_id, @facilities_by_id)}
          </:col>
          <:col :let={correction} label="Change">{change_label(correction)}</:col>
          <:col :let={correction} label="Reason">{correction.reason}</:col>
          <:col :let={correction} label="By">
            {Map.get(@users_by_id, correction.corrected_by_id, "Unknown user")}
          </:col>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: LabReporting.subscribe_lab_tests()

    scope = facility_scope(socket.assigns.current_scope.user)
    cases = list_cases(scope)
    facilities = Geography.list_facilities()
    facilities_by_id = Map.new(facilities, &{&1.id, &1.name})
    lab_tests = list_lab_tests(scope)
    lab_tests_by_id = Map.new(lab_tests, &{&1.id, &1})

    socket =
      socket
      |> assign(:scope, scope)
      |> assign(:result_options, @result_options)
      |> assign(:cases_by_id, Map.new(cases, &{&1.id, &1}))
      |> assign(:facilities_by_id, facilities_by_id)
      |> assign(:users_by_id, Map.new(Accounts.list_users(), &{&1.id, user_label(&1)}))
      |> assign(:case_options, Enum.map(cases, &{case_option_label(&1, facilities_by_id), &1.id}))
      |> assign(:lab_test_count, length(lab_tests))
      |> assign(:lab_tests_by_id, lab_tests_by_id)
      |> assign(:correcting, nil)
      |> assign_corrections()
      |> assign_correction_notices()
      |> assign_form(LabReporting.change_lab_test(%LabTest{}))
      |> stream(:lab_tests, lab_tests)

    {:ok, socket}
  end

  # Same role-based scope CaseLive.Index establishes (see its own
  # comment for the full reasoning) - duplicated here rather than
  # shared, same small-per-module-helper convention `with_reporter/2`
  # already set.
  defp facility_scope(%{role: :health_worker, facility_id: nil}), do: :unassigned
  defp facility_scope(%{role: :health_worker, facility_id: facility_id}), do: {:locked, facility_id}
  defp facility_scope(_user), do: :unrestricted

  defp list_cases(:unrestricted), do: CaseManagement.list_cases()
  defp list_cases(:unassigned), do: []
  defp list_cases({:locked, facility_id}), do: CaseManagement.list_cases_by_facility(facility_id)

  defp list_lab_tests(:unrestricted), do: LabReporting.list_lab_tests()
  defp list_lab_tests(:unassigned), do: []
  defp list_lab_tests({:locked, facility_id}), do: LabReporting.list_lab_tests_by_facility(facility_id)

  # The correction history follows the same facility scope as the test
  # list: a health worker sees corrections to their own facility's
  # tests only.
  defp assign_corrections(socket) do
    visible_ids = socket.assigns.lab_tests_by_id

    corrections =
      Enum.filter(LabReporting.list_corrections(), &Map.has_key?(visible_ids, &1.lab_test_id))

    assign(socket, :corrections, corrections)
  end

  # Corrections to results on tests this user requested, not yet marked
  # as seen - see LabReporting.list_correction_notices/1.
  defp assign_correction_notices(socket) do
    assign(
      socket,
      :correction_notices,
      LabReporting.list_correction_notices(socket.assigns.current_scope.user.id)
    )
  end

  @impl true
  def handle_event("save", %{"lab_test" => params}, socket) do
    case check_scope(params, socket.assigns.scope) do
      :ok ->
        case LabReporting.request_test(with_requester(params, socket)) do
          {:ok, _lab_test} ->
            {:noreply,
             socket
             |> put_flash(:info, "Lab test requested.")
             |> assign_form(LabReporting.change_lab_test(%LabTest{}))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
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
    recorder = socket.assigns.current_scope.user

    case to_result(result) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unrecognized result value.")}

      result_atom ->
        case LabReporting.record_result(lab_test, result_atom, recorder) do
          {:ok, updated} ->
            # No manual stream_insert here - same "rely on the PubSub
            # round-trip" pattern CaseLive.Index's own handle_event("save",
            # ...)/"advance_status" already use: record_result/3's own
            # broadcast lands right back on this LiveView's handle_info
            # below.
            {:noreply,
             put_flash(socket, :info, "Result recorded: #{result_label(updated.result)}.")}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "Only a lab officer can record a lab result.")}

          {:error, :already_resulted} ->
            {:noreply, put_flash(socket, :error, "This test already has a recorded result.")}
        end
    end
  end

  # Opening the correction panel is gated the same way the buttons are,
  # so a forged event can't even show the form to someone who couldn't
  # submit it. Submitting re-checks everything in LabReporting anyway.
  def handle_event("start_correction", %{"id" => id, "mode" => mode}, socket) do
    lab_test = LabReporting.get_lab_test!(id)

    cond do
      not LabReporting.can_correct_results?(socket.assigns.current_scope.user.role) ->
        {:noreply, put_flash(socket, :error, correction_error(:unauthorized))}

      to_mode(mode) == nil ->
        {:noreply, put_flash(socket, :error, "Unrecognized correction type.")}

      true ->
        {:noreply,
         socket
         |> assign(:correcting, %{lab_test: lab_test, mode: to_mode(mode)})
         |> assign(:correction_form, empty_correction_form())}
    end
  end

  def handle_event("cancel_correction", _params, socket) do
    {:noreply, assign(socket, :correcting, nil)}
  end

  def handle_event("acknowledge_correction", %{"id" => id}, socket) do
    case LabReporting.acknowledge_correction(id, socket.assigns.current_scope.user) do
      {:ok, _acknowledgement} ->
        {:noreply, assign_correction_notices(socket)}

      {:error, :not_requester} ->
        {:noreply,
         put_flash(socket, :error, "Only the person who requested this test can mark it as seen.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That notice couldn't be found.")}
    end
  end

  def handle_event("submit_correction", %{"correction" => params}, socket) do
    lab_test = LabReporting.get_lab_test!(params["lab_test_id"])
    corrector = socket.assigns.current_scope.user
    reason = Map.get(params, "reason", "")

    result =
      case to_mode(params["mode"]) do
        :correct ->
          LabReporting.correct_result(
            lab_test,
            to_result(Map.get(params, "new_result", "")),
            reason,
            corrector
          )

        :withdraw ->
          LabReporting.withdraw_result(lab_test, reason, corrector)

        nil ->
          {:error, :unrecognized_mode}
      end

    case result do
      {:ok, %LabTest{status: :entered_in_error}} ->
        {:noreply,
         socket
         |> assign(:correcting, nil)
         |> put_flash(:info, "Result withdrawn. The case's classification has been updated.")}

      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:correcting, nil)
         |> put_flash(
           :info,
           "Result corrected to #{result_label(updated.result)}. " <>
             "The case's classification has been updated."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :correction_form, to_form(changeset, as: "correction"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, correction_error(reason))}
    end
  end

  # There's no `facility_id` field on this form to lock the way
  # CaseLive.Index/DrugLive.Index/HospitalLive.Index lock theirs - the
  # thing being chosen is a `case_id`, and which facility that implies
  # comes from the case itself. The `case_options` dropdown is already
  # filtered to the worker's own facility in `mount/3`, but (same
  # "don't trust the button being hidden" precedent every other
  # handler in this project follows) a forged event could still submit
  # a `case_id` for a different facility, so this re-checks the chosen
  # case's actual `facility_id` server-side before it ever reaches
  # `LabReporting.request_test/1`.
  defp check_scope(_params, :unrestricted), do: :ok

  defp check_scope(_params, :unassigned),
    do: {:error, "You need to be assigned to a facility before requesting a lab test."}

  defp check_scope(%{"case_id" => case_id}, {:locked, facility_id}) do
    case CaseManagement.get_case!(case_id) do
      %{facility_id: ^facility_id} -> :ok
      _other_facility -> {:error, "You can only request tests for cases at your own facility."}
    end
  rescue
    Ecto.NoResultsError -> {:error, "That case could not be found."}
  end

  defp check_scope(_params, {:locked, _facility_id}),
    do: {:error, "Select a case before requesting a test."}

  # Only tests in this user's scope - on cases at their facility, for a
  # health worker - are added (Iteration 20): before, every broadcast
  # test was, so a health worker's page picked up other facilities'
  # tests live until a reload.
  @impl true
  def handle_info({:created, %LabTest{} = lab_test}, socket) do
    if in_scope?(socket.assigns.scope, lab_test) do
      {:noreply,
       socket
       |> stream_insert(:lab_tests, lab_test, at: 0)
       |> update(:lab_test_count, &(&1 + 1))
       |> update(:lab_tests_by_id, &Map.put(&1, lab_test.id, lab_test))}
    else
      {:noreply, socket}
    end
  end

  # A correction or withdrawal arrives as an ordinary `{:updated, _}` -
  # refresh the history alongside the row, since one may just have been
  # added. Only for tests already in this viewer's scope, so a health
  # worker's page doesn't pick up another facility's test this way.
  def handle_info({:updated, %LabTest{} = lab_test}, socket) do
    if Map.has_key?(socket.assigns.lab_tests_by_id, lab_test.id) do
      {:noreply,
       socket
       |> stream_insert(:lab_tests, lab_test)
       |> update(:lab_tests_by_id, &Map.put(&1, lab_test.id, lab_test))
       |> assign_corrections()
       |> assign_correction_notices()}
    else
      # Not in this viewer's scope. Before Iteration 20 this branch still
      # streamed the test in, which defeated the check above.
      {:noreply, socket}
    end
  end

  # A test's facility is its case's facility. Looked up rather than read
  # from `@cases_by_id`, which only holds the cases that existed at
  # mount - a test on a case reported since then must still count.
  defp in_scope?(:unrestricted, _lab_test), do: true

  defp in_scope?({:locked, facility_id}, %LabTest{case_id: case_id}) do
    CaseManagement.get_case!(case_id).facility_id == facility_id
  rescue
    Ecto.NoResultsError -> false
  end

  defp in_scope?(_scope, _lab_test), do: false

  defp to_result(result) when result in ~w(positive negative inconclusive) do
    String.to_existing_atom(result)
  end

  defp to_result(_result), do: nil

  defp to_mode("correct"), do: :correct
  defp to_mode("withdraw"), do: :withdraw
  defp to_mode(_mode), do: nil

  defp empty_correction_form do
    to_form(%{"new_result" => nil, "reason" => ""}, as: "correction")
  end

  defp correction_error(:unauthorized),
    do: "Only a lab officer or MOH admin can correct or withdraw a result."

  defp correction_error(:not_correctable),
    do: "Only an issued result can be corrected or withdrawn."

  defp correction_error(:unchanged), do: "That's already this test's result."
  defp correction_error(_reason), do: "That correction couldn't be saved."

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

  defp correction_case_label(%LabResultCorrection{} = correction, lab_tests_by_id, cases_by_id, facilities_by_id) do
    case Map.get(lab_tests_by_id, correction.lab_test_id) do
      nil -> "Unknown test"
      lab_test -> case_label(lab_test, cases_by_id, facilities_by_id)
    end
  end

  defp change_label(%LabResultCorrection{kind: :corrected} = correction) do
    "#{result_label(correction.previous_result)} → #{result_label(correction.new_result)}"
  end

  defp change_label(%LabResultCorrection{kind: :entered_in_error} = correction) do
    "#{result_label(correction.previous_result)} withdrawn (entered in error)"
  end

  defp result_label(nil), do: ""
  defp result_label(result), do: Phoenix.Naming.humanize(result)

  # Who entered a result. A resulted test with no `resulted_by_id` was
  # entered before Iteration 15 started recording it - said plainly
  # rather than left blank, so it doesn't read as missing data.
  defp resulted_by_label(%LabTest{status: :pending}, _users_by_id), do: ""
  defp resulted_by_label(%LabTest{resulted_by_id: nil}, _users_by_id), do: "Not recorded"

  defp resulted_by_label(%LabTest{resulted_by_id: user_id}, users_by_id),
    do: Map.get(users_by_id, user_id, "Unknown user")

  # Same "email, else phone" identity rule CaseLive.Index's
  # reporter_label/1 uses.
  defp user_label(%{email: email}) when is_binary(email), do: email
  defp user_label(%{phone: phone}) when is_binary(phone), do: phone
  defp user_label(_user), do: "Unknown user"

  defp status_label(:entered_in_error), do: "Withdrawn"
  defp status_label(status), do: Phoenix.Naming.humanize(status)

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:resulted), do: "badge-success"
  defp status_badge_class(:corrected), do: "badge-info"
  defp status_badge_class(:entered_in_error), do: "badge-ghost"

  # Mirrors LabReporting.record_result/3's own checks - shown here
  # purely to decide whether to render the buttons at all. The context
  # re-checks both the same way regardless, since hiding a button is a
  # UI nicety, not an authorization boundary on its own (same precedent
  # CaseLive.Index.can_advance_status?/2 already set).
  defp can_record_result?(current_scope, %LabTest{status: :pending}) do
    LabReporting.can_record_results?(current_scope.user.role)
  end

  defp can_record_result?(_current_scope, _lab_test), do: false

  # Same idea for corrections: only an issued (resulted or already
  # corrected) result, and only for roles LabReporting allows.
  defp can_correct?(current_scope, %LabTest{status: status})
       when status in [:resulted, :corrected] do
    LabReporting.can_correct_results?(current_scope.user.role)
  end

  defp can_correct?(_current_scope, _lab_test), do: false
end
