defmodule ZamHealthWatchWeb.GuidanceLive.Index do
  use ZamHealthWatchWeb, :live_view

  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Guidance

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Guidance
        <:subtitle>
          Case-definition and response guidance for each disease ZamHealthWatch tracks - what to look for, what to do immediately, when to refer, and how urgently to report it.
        </:subtitle>
      </.header>

      <div class="flex flex-wrap gap-2 my-4">
        <.link
          :for={disease <- @diseases}
          patch={~p"/guidance/#{disease}"}
          class={["btn btn-sm", disease == @selected && "btn-primary"]}
        >
          {Case.disease_label(disease)}
        </.link>
      </div>

      <div :if={@content} class="space-y-4">
        <div>
          <h3 class="font-semibold">Case definition</h3>
          <p>{@content.case_definition}</p>
        </div>

        <div>
          <h3 class="font-semibold">Immediate actions</h3>
          <ul class="list-disc list-inside space-y-1">
            <li :for={action <- @content.immediate_actions}>{action}</li>
          </ul>
        </div>

        <div>
          <h3 class="font-semibold">When to refer</h3>
          <p>{@content.when_to_refer}</p>
        </div>

        <div>
          <h3 class="font-semibold">Reporting</h3>
          <p>{@content.reporting}</p>
        </div>
      </div>

      <p :if={!@content} id="no-disease-selected" class="text-sm text-base-content/60">
        Select a disease above to see its guidance.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :diseases, Guidance.list_diseases())}
  end

  @impl true
  def handle_params(%{"disease" => disease_param}, _uri, socket) do
    disease = safe_to_disease(disease_param, socket.assigns.diseases)

    socket =
      socket
      |> assign(:selected, disease)
      |> assign(:content, disease && Guidance.get(disease))

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket |> assign(:selected, nil) |> assign(:content, nil)}
  end

  # `disease_param` comes straight from the URL path, never trusted
  # enough to hand to `String.to_existing_atom/1` (or worse,
  # `String.to_atom/1`) directly - matched instead against the known,
  # already-atomized `diseases` list from `mount/3`. An unrecognized
  # value (a typo, or someone probing the URL) just lands on "no
  # disease selected" rather than crashing the LiveView or growing the
  # atom table from attacker-controlled input.
  defp safe_to_disease(disease_param, diseases) do
    Enum.find(diseases, &(Atom.to_string(&1) == disease_param))
  end
end
