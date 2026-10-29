defmodule ZamHealthWatch.GuidanceTest do
  use ExUnit.Case, async: true

  alias ZamHealthWatch.CaseManagement.Case
  alias ZamHealthWatch.Guidance

  describe "list_diseases/0" do
    test "returns every disease Case.disease_options/0 defines, in the same order" do
      assert Guidance.list_diseases() ==
               Enum.map(Case.disease_options(), fn {_label, disease} -> disease end)
    end
  end

  describe "get/1" do
    test "returns content with all four sections for every listed disease" do
      for disease <- Guidance.list_diseases() do
        assert %{
                 case_definition: definition,
                 immediate_actions: actions,
                 when_to_refer: when_to_refer,
                 reporting: reporting
               } = Guidance.get(disease)

        assert is_binary(definition) and definition != ""
        assert is_list(actions) and actions != []
        assert is_binary(when_to_refer) and when_to_refer != ""
        assert is_binary(reporting) and reporting != ""
      end
    end

    test "returns nil for a disease it has no content for" do
      refute Guidance.get(:not_a_real_disease)
    end
  end
end
