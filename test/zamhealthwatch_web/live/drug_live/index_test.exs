defmodule ZamHealthWatchWeb.DrugLive.IndexTest do
  use ZamHealthWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ZamHealthWatch.AccountsFixtures
  import ZamHealthWatch.GeographyFixtures
  import ZamHealthWatch.DrugAvailabilityFixtures

  alias ZamHealthWatch.CaseManagement
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

  describe "facility scoping for health workers" do
    test "an unassigned health_worker sees a get-assigned message instead of the form", %{
      conn: conn
    } do
      user = user_fixture() |> set_role(:health_worker)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/drugs")

      assert html =~ "haven&#39;t been assigned to a facility yet"
      assert html =~ "Manage users"
      refute html =~ "id=\"drug-stock-form\""
    end

    test "an assigned health_worker only sees drug stock at their own facility", %{conn: conn} do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture(%{name: "Ndola Teaching Hospital"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      drug_stock_fixture(%{facility_id: facility.id, medicine: :ors})
      drug_stock_fixture(%{facility_id: other_facility.id, medicine: :al})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/drugs")

      # `medicine` isn't a reliable isolation signal - the "Medicine"
      # <select> always lists every medicine (including
      # "Artemether-Lumefantrine") as a choice for a *new* record,
      # regardless of what's already in the scoped list below it. The
      # "N submitted so far" count and the other facility's own name
      # (absent once the facility field is locked) are what actually
      # reflect the scoped query.
      assert html =~ "1 record submitted so far."
      refute html =~ "Ndola Teaching Hospital"
    end

    test "an assigned health_worker's form shows their facility locked, not a select", %{
      conn: conn
    } do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      user = user_fixture() |> set_role(:health_worker, facility.id)

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/drugs")

      assert html =~ "Kabwata Clinic"
      refute has_element?(lv, "select[name=\"drug_stock[facility_id]\"]")
    end

    test "a forged facility_id is overridden with the health_worker's own facility", %{
      conn: conn
    } do
      facility = facility_fixture(%{name: "Kabwata Clinic"})
      other_facility = facility_fixture()
      user = user_fixture() |> set_role(:health_worker, facility.id)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/drugs")

      render_submit(lv, "save", %{
        "drug_stock" => %{
          "facility_id" => other_facility.id,
          "medicine" => "al",
          "quantity_on_hand" => "30",
          "reorder_level" => "50"
        }
      })

      assert [stock] = DrugAvailability.list_drug_stocks()
      assert stock.facility_id == facility.id
    end
  end

  describe "supply alerts" do
    test "a health worker sees their own facility's alert, not another facility's", %{conn: conn} do
      own = facility_fixture(%{name: "Own Clinic"})
      other = facility_fixture(%{name: "Other Clinic"})
      user = user_fixture() |> set_role(:health_worker, own.id)

      for facility <- [own, other] do
        {:ok, _case} =
          CaseManagement.create_case(%{
            disease: :cholera,
            facility_id: facility.id,
            reported_by_id: user.id
          })

        drug_stock_fixture(%{
          facility_id: facility.id,
          medicine: :iv_fluids,
          quantity_on_hand: 15,
          reorder_level: 30
        })
      end

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/drugs")

      assert has_element?(lv, "#supply-alert-#{own.id}-iv_fluids", "15 / 30")
      assert has_element?(lv, "#supply-alert-#{own.id}-iv_fluids", "1 Cholera case")
      refute has_element?(lv, "#supply-alert-#{other.id}-iv_fluids")
    end

    test "shows no alert banner when nothing short is needed", %{conn: conn} do
      facility = facility_fixture()
      user = user_fixture() |> set_role(:district_officer)

      drug_stock_fixture(%{
        facility_id: facility.id,
        medicine: :al,
        quantity_on_hand: 1,
        reorder_level: 60
      })

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/drugs")

      refute has_element?(lv, "#supply-alerts")
    end

    test "an alert appears live when a case makes a shortage matter", %{conn: conn} do
      facility = facility_fixture()
      user = user_fixture() |> set_role(:district_officer)

      drug_stock_fixture(%{
        facility_id: facility.id,
        medicine: :ors,
        quantity_on_hand: 5,
        reorder_level: 50
      })

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/drugs")
      refute has_element?(lv, "#supply-alert-#{facility.id}-ors")

      {:ok, _case} =
        CaseManagement.create_case(%{
          disease: :cholera,
          facility_id: facility.id,
          reported_by_id: user.id
        })

      assert has_element?(lv, "#supply-alert-#{facility.id}-ors")
    end

    test "a health worker's list doesn't pick up stock recorded live at other facilities", %{
      conn: conn
    } do
      own = facility_fixture()
      other = facility_fixture()
      user = user_fixture() |> set_role(:health_worker, own.id)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/drugs")

      other_stock = drug_stock_fixture(%{facility_id: other.id})
      own_stock = drug_stock_fixture(%{facility_id: own.id})

      assert has_element?(lv, "#drug_stocks-#{own_stock.id}")
      refute has_element?(lv, "#drug_stocks-#{other_stock.id}")
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
