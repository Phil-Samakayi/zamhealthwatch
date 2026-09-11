defmodule ZamHealthWatchWeb.DrugLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures

  alias ZamHealthWatch.DrugAvailability

  describe "Drug stock list" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/drugs")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders the form and an empty state when there are no records", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/drugs")

      assert html =~ "Record drug stock"
      assert html =~ "Select a facility"
      assert html =~ "No drug stock recorded yet."
    end

    test "lists existing records", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})

      drug_stock_fixture(%{
        facility_id: facility.id,
        medicine: :ors,
        quantity_on_hand: 10,
        reorder_level: 50
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/drugs")

      assert html =~ "Kabwata Clinic"
      assert html =~ "ORS (Oral Rehydration Salts)"
      refute html =~ "No drug stock recorded yet."
    end
  end

  describe "record stock form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "records stock with valid data", %{conn: conn, user: user} do
      facility = facility_fixture()
      {:ok, lv, _html} = live(conn, ~p"/drugs")

      result =
        lv
        |> form("#drug-stock-form", %{
          "drug_stock" => %{
            "facility_id" => facility.id,
            "medicine" => "al",
            "quantity_on_hand" => "30",
            "reorder_level" => "50"
          }
        })
        |> render_submit()

      assert result =~ "Drug stock recorded."

      assert [stock] = DrugAvailability.list_drug_stocks()
      assert stock.facility_id == facility.id
      assert stock.medicine == :al
      assert stock.reported_by_id == user.id
    end

    test "renders errors with invalid data (no facility selected)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/drugs")

      result =
        lv
        |> form("#drug-stock-form", %{
          "drug_stock" => %{
            "facility_id" => "",
            "medicine" => "al",
            "quantity_on_hand" => "30",
            "reorder_level" => "50"
          }
        })
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "ignores a client-supplied reported_by_id and uses the current user", %{
      conn: conn,
      user: user
    } do
      facility = facility_fixture()
      other_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/drugs")

      render_submit(lv, "save", %{
        "drug_stock" => %{
          "facility_id" => facility.id,
          "medicine" => "al",
          "quantity_on_hand" => "30",
          "reorder_level" => "50",
          "reported_by_id" => other_user.id
        }
      })

      assert [stock] = DrugAvailability.list_drug_stocks()
      assert stock.reported_by_id == user.id
    end

    test "broadcasts a newly recorded stock entry to other viewers live", %{conn: conn} do
      facility = facility_fixture(%{name: "Ndola Teaching Hospital"})

      {:ok, lv1, _html} = live(conn, ~p"/drugs")
      {:ok, lv2, _html} = live(conn, ~p"/drugs")

      lv1
      |> form("#drug-stock-form", %{
        "drug_stock" => %{
          "facility_id" => facility.id,
          "medicine" => "ciprofloxacin",
          "quantity_on_hand" => "30",
          "reorder_level" => "50"
        }
      })
      |> render_submit()

      assert render(lv2) =~ "Ndola Teaching Hospital"
      assert render(lv2) =~ "Ciprofloxacin"
    end
  end

  describe "stock status badge" do
    test "shows a shortage badge when quantity is below reorder level", %{conn: conn} do
      facility = facility_fixture()
      drug_stock_fixture(%{facility_id: facility.id, quantity_on_hand: 10, reorder_level: 50})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/drugs")

      assert has_element?(lv, "span.badge-error", "Shortage")
    end

    test "shows an adequate badge when quantity is at or above reorder level", %{conn: conn} do
      facility = facility_fixture()
      drug_stock_fixture(%{facility_id: facility.id, quantity_on_hand: 60, reorder_level: 50})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/drugs")

      assert has_element?(lv, "span.badge-success", "Adequate")
    end
  end
end
