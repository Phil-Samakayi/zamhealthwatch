defmodule ZamHealthWatch.Guidance do
  @moduledoc """
  The Guidance context.

  Health Worker Portal, per the project brief, is "facility-level
  login, case entry, guidance content." Login (`mix phx.gen.auth`,
  Iteration 0) and case entry (`CaseLive.Index`, Iteration 1) already
  exist - this context closes the one piece that didn't: point-of-care
  reference content a health worker can look up while assessing a
  patient, for each of the five diseases this project tracks.

  Deliberately static, not database-backed - no new table, no
  `Repo` call anywhere in this module. There's no real use case yet for
  an MOH admin editing this content through a UI (no one has asked for
  that, and standard case-definition/referral guidance doesn't change
  often enough to justify the extra moving parts a schema, changeset,
  and admin screen would add) - same "no lifecycle without a real use
  case" call every other single-purpose piece of this project already
  makes. If that need ever shows up, migrating this module's content
  into a schema is a contained, mechanical change - the public API
  (`list_diseases/0`, `get/1`) wouldn't have to change shape for
  callers.

  Content is general, standard public-health case-definition and
  response guidance (WHO/IMCI-style: how to recognize a case, what to
  do immediately, when it's severe enough to refer, how urgently to
  report it) - deliberately *not* specific drug names, dosages, or
  treatment regimens, which vary by current national guidelines and
  local antimicrobial resistance patterns and would be actively unsafe
  to hard-code into an app that doesn't track guideline versions.
  Where a dose or drug choice matters, this content points the reader
  to "national treatment guidelines" rather than guessing at one -
  same spirit as this project declining to invent SMS gateway response
  shapes it couldn't verify.

  Keyed by the same `disease` atoms `CaseManagement.Case` already
  defines (`:cholera`, `:malaria`, `:typhoid`, `:covid19`, `:measles`)
  and ordered via `Case.disease_options/0` - the single source of
  truth for disease ordering/labels this project already established,
  reused here rather than duplicated a fourth time.
  """

  alias ZamHealthWatch.CaseManagement.Case

  @guidance %{
    cholera: %{
      case_definition:
        "In a cholera-endemic or outbreak area: acute watery diarrhoea, with or without vomiting, in a patient aged 2 years or older. Outside a known outbreak, suspect cholera in any patient aged 5 or older with severe dehydration or death from acute watery diarrhoea.",
      immediate_actions: [
        "Assess dehydration status (mild/moderate/severe) before anything else.",
        "Start oral rehydration immediately for mild-to-moderate dehydration; escalate to IV fluids per facility protocol for severe dehydration.",
        "Isolate the patient where possible and apply safe stool disposal and handwashing precautions.",
        "Collect a stool sample for lab confirmation where capacity allows."
      ],
      when_to_refer:
        "Severe dehydration, persistent vomiting that prevents oral rehydration, or any danger sign (lethargy, inability to drink) - refer immediately to a facility with IV rehydration capacity.",
      reporting:
        "Immediately notifiable. Report to the District Health Office the same day a suspected case is seen, in addition to logging it here."
    },
    malaria: %{
      case_definition:
        "Fever, or a history of fever in the last 48 hours, with no other obvious cause - confirmed by a positive rapid diagnostic test (RDT) or microscopy where available.",
      immediate_actions: [
        "Perform or request an RDT/microscopy before treating, where possible.",
        "Treat confirmed uncomplicated malaria per current national treatment guidelines.",
        "Assess for danger signs of severe malaria: impaired consciousness, repeated vomiting, convulsions, severe anaemia, or difficulty breathing."
      ],
      when_to_refer:
        "Any sign of severe malaria; a confirmed case in a child under 5 or a pregnant patient with any complicating factor; or treatment failure - refer to a facility with inpatient capacity.",
      reporting:
        "Log the case and test result here on the normal reporting cadence. A local cluster of cases is itself a signal - notify the District Health Office if several cases trace to the same area in a short window."
    },
    typhoid: %{
      case_definition:
        "Prolonged fever (more than 3 days) with one or more of: headache, malaise, loss of appetite, abdominal discomfort, or relative bradycardia - confirmed by blood culture or Widal test where available.",
      immediate_actions: [
        "Collect a blood sample for culture before starting antibiotics, where feasible.",
        "Begin antibiotic therapy per current national/local resistance guidelines.",
        "Advise on safe food handling and water hygiene, especially if the patient handles food or cares for children."
      ],
      when_to_refer:
        "Signs of intestinal perforation or bleeding (severe abdominal pain, rigidity, melena), persistent high fever despite treatment, or any danger sign - refer immediately.",
      reporting:
        "Log here on the normal cadence. Notify the District Health Office if more than one case links to the same household, school, or water source - a possible common-source outbreak."
    },
    covid19: %{
      case_definition:
        "Acute respiratory illness (fever, cough, shortness of breath, loss of taste/smell, or other compatible symptoms), confirmed by a positive test where testing is available, or meeting the facility's current working case definition.",
      immediate_actions: [
        "Isolate the patient and apply respiratory infection-prevention precautions.",
        "Check oxygen saturation where a pulse oximeter is available.",
        "Provide supportive care (rest, fluids, antipyretics) for mild cases."
      ],
      when_to_refer:
        "Oxygen saturation below the facility's referral threshold, difficulty breathing, confusion, inability to maintain fluids, or any other danger sign - refer immediately to a facility with oxygen/inpatient capacity.",
      reporting:
        "Log here on the normal cadence. A cluster of cases from the same facility, school, or gathering should be flagged to the District Health Office promptly."
    },
    measles: %{
      case_definition:
        "Fever and a non-vesicular, maculopapular rash, with at least one of: cough, runny nose, or conjunctivitis.",
      immediate_actions: [
        "Isolate the patient - measles spreads very easily.",
        "Give vitamin A per national protocol.",
        "Check and record the patient's vaccination status."
      ],
      when_to_refer:
        "Signs of complications (pneumonia, severe dehydration, encephalitis symptoms, or any danger sign), or any case in a child under 1 or a malnourished child - refer promptly.",
      reporting:
        "Immediately notifiable, given its outbreak potential. Report to the District Health Office the same day a suspected case is seen, in addition to logging it here."
    }
  }

  @doc """
  Returns every disease with guidance content, in the same display
  order as `CaseManagement.Case.disease_options/0`.

  ## Examples

      iex> list_diseases()
      [:cholera, :malaria, :typhoid, :covid19, :measles]

  """
  def list_diseases do
    Case.disease_options() |> Enum.map(fn {_label, disease} -> disease end)
  end

  @doc """
  Returns the guidance content for one disease, or `nil` if this
  module has none for it (defensive only - every value
  `Case.disease_options/0` can produce has an entry here; this exists
  so a stale or mistyped param from the URL fails gracefully in the
  LiveView rather than raising).

  ## Examples

      iex> get(:cholera)
      %{case_definition: "...", immediate_actions: [...], when_to_refer: "...", reporting: "..."}

      iex> get(:not_a_disease)
      nil

  """
  def get(disease) when is_atom(disease), do: Map.get(@guidance, disease)
end
