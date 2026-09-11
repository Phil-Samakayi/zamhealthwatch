defmodule ZamHealthWatchWeb.VaccinationLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.VaccinationMonitoringFixtures

  alias ZamHealthWatch.VaccinationMonitoring

  describe "Vaccination coverage list" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/vaccinations")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the form and an empty state when there are no records", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/vaccinations")

      assert html =~ "Record vaccination coverage"
      assert html =~ "Select a district"
      assert html =~ "No vaccination coverage recorded yet."
    end

    test "lists existing records", %{conn: conn} do
      district = district_fixture(%{name: "Monze"})

      vaccination_record_fixture(%{
        district_id: district.id,
        antigen: :bcg,
        campaign: "Routine - Sep 2026"
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/vaccinations")

      assert html =~ "Monze"
      assert html =~ "BCG"
      assert html =~ "Routine - Sep 2026"
      refute html =~ "No vaccination coverage recorded yet."
    end
  end

  describe "record coverage form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "records coverage with valid data", %{conn: conn, user: user} do
      district = district_fixture()
      {:ok, lv, _html} = live(conn, ~p"/vaccinations")

      result =
        lv
        |> form("#vaccination-form", %{
          "vaccination_record" => %{
            "district_id" => district.id,
            "antigen" => "bcg",
            "campaign" => "Routine - Sep 2026",
            "doses_administered" => "45",
            "target_population" => "60"
          }
        })
        |> render_submit()

      assert result =~ "Vaccination coverage recorded."

      assert [record] = VaccinationMonitoring.list_vaccination_records()
      assert record.district_id == district.id
      assert record.antigen == :bcg
      assert record.reported_by_id == user.id
    end

    test "renders errors with invalid data (no district selected)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/vaccinations")

      result =
        lv
        |> form("#vaccination-form", %{
          "vaccination_record" => %{
            "district_id" => "",
            "antigen" => "bcg",
            "campaign" => "Routine",
            "doses_administered" => "10",
            "target_population" => "20"
          }
        })
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "ignores a client-supplied reported_by_id and uses the current user", %{
      conn: conn,
      user: user
    } do
      district = district_fixture()
      other_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/vaccinations")

      render_submit(lv, "save", %{
        "vaccination_record" => %{
          "district_id" => district.id,
          "antigen" => "bcg",
          "campaign" => "Routine",
          "doses_administered" => "10",
          "target_population" => "20",
          "reported_by_id" => other_user.id
        }
      })

      assert [record] = VaccinationMonitoring.list_vaccination_records()
      assert record.reported_by_id == user.id
    end

    test "broadcasts a newly recorded coverage entry to other viewers live", %{conn: conn} do
      district = district_fixture(%{name: "Ndola"})

      {:ok, lv1, _html} = live(conn, ~p"/vaccinations")
      {:ok, lv2, _html} = live(conn, ~p"/vaccinations")

      lv1
      |> form("#vaccination-form", %{
        "vaccination_record" => %{
          "district_id" => district.id,
          "antigen" => "opv",
          "campaign" => "Routine",
          "doses_administered" => "10",
          "target_population" => "20"
        }
      })
      |> render_submit()

      assert render(lv2) =~ "Ndola"
      assert render(lv2) =~ "OPV (Polio)"
    end
  end

  describe "coverage badge" do
    test "shows a success badge at or above 80% coverage", %{conn: conn} do
      district = district_fixture()

      vaccination_record_fixture(%{
        district_id: district.id,
        doses_administered: 80,
        target_population: 100
      })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/vaccinations")

      assert has_element?(lv, "span.badge-success", "80.0%")
    end

    test "shows a warning badge between 50% and 80% coverage", %{conn: conn} do
      district = district_fixture()

      vaccination_record_fixture(%{
        district_id: district.id,
        doses_administered: 60,
        target_population: 100
      })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/vaccinations")

      assert has_element?(lv, "span.badge-warning", "60.0%")
    end

    test "shows an error badge below 50% coverage", %{conn: conn} do
      district = district_fixture()

      vaccination_record_fixture(%{
        district_id: district.id,
        doses_administered: 20,
        target_population: 100
      })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/vaccinations")

      assert has_element?(lv, "span.badge-error", "20.0%")
    end
  end
end
