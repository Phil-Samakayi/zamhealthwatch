# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ZamHealthWatch.Repo.insert!(%ZamHealthWatch.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias ZamHealthWatch.Geography
alias ZamHealthWatch.Geography.{District, Facility}
alias ZamHealthWatch.Repo

# A handful of real Zambian districts/facilities so there's something to
# pick from CaseLive.Index's facility dropdown in dev - not exhaustive
# reference data, just enough to actually exercise the app locally.
#
# Districts are seeded even though Facility.changeset/2 can't attach a
# facility to one yet (district_id isn't cast - see docs/ITERATIONS.md,
# Iteration 1's Epidemiology Dashboard decisions) - they're harmless to
# have around now and save reseeding once that gap closes.
#
# Idempotent: safe to re-run (`mix run priv/repo/seeds.exs` again) without
# creating duplicates, since neither `name` column has a unique constraint
# to rely on for `Repo.insert!/2`'s usual upsert options.
districts = [
  %{name: "Lusaka", province: "Lusaka"},
  %{name: "Ndola", province: "Copperbelt"},
  %{name: "Monze", province: "Southern"}
]

for attrs <- districts do
  unless Repo.get_by(District, name: attrs.name) do
    {:ok, _district} = Geography.create_district(attrs)
  end
end

# Each facility now needs a `code` (Iteration 2: SmsReporting addresses
# a facility by this short code from inside a plain-text SMS, not by
# name or id). If you seeded facilities before this change, re-running
# this script won't backfill their code - `Repo.get_by(Facility, name:
# ...)` below will find the old row by name and skip it. Run
# `mix ecto.reset` instead for a clean slate; there's no real data here
# yet worth preserving over a backfill migration for four rows.
facilities = [
  {"University Teaching Hospital", "UTH"},
  {"Kabwata Clinic", "KBW"},
  {"Ndola Teaching Hospital", "NTH"},
  {"Monze Mission Hospital", "MMH"}
]

for {name, code} <- facilities do
  unless Repo.get_by(Facility, name: name) do
    {:ok, _facility} = Geography.create_facility(%{name: name, code: code})
  end
end

IO.puts("Seeded #{length(districts)} districts and #{length(facilities)} facilities.")
