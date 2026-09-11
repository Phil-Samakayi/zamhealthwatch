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

# Looked up by name, not carried around as an in-memory map keyed from
# the loop above - the districts loop above only creates a district
# when it's missing, so a district created on an earlier run (and left
# untouched on this one) still needs its id fetched from the DB here.
district_ids_by_name =
  Map.new(districts, fn %{name: name} -> {name, Repo.get_by!(District, name: name).id} end)

# Each facility now needs a `code` (Iteration 2: SmsReporting addresses
# a facility by this short code from inside a plain-text SMS, not by
# name or id), an approximate latitude/longitude (GIS Mapping - town-
# centre coordinates, not surveyed exact addresses, demo seed data for
# MapLive.Index), and now a `district_id` (closing the by-district
# aggregation gap Iteration 1's Epidemiology Dashboard originally
# deferred - see docs/ITERATIONS.md) - the real district each facility
# is actually in.
#
# Upsert by name, not "skip if the name already exists": a facility
# schema field added after your DB was first seeded (this has already
# happened three times now - `code`, `latitude`/`longitude`, and
# `district_id`) needs to land on the row that's already there, not
# silently stay nil forever because `Repo.get_by(Facility, name: ...)`
# found something and moved on. `mix run priv/repo/seeds.exs` safely
# backfills new facility fields onto existing rows without touching
# `users` at all - see the GIS Mapping entry in docs/ITERATIONS.md for
# why that distinction matters (it used to mean `mix ecto.reset`,
# which also wipes whichever account you're logged in as).
facilities = [
  {"University Teaching Hospital", "UTH", -15.4067, 28.3229, "Lusaka"},
  {"Kabwata Clinic", "KBW", -15.4300, 28.2900, "Lusaka"},
  {"Ndola Teaching Hospital", "NTH", -12.9587, 28.6366, "Ndola"},
  {"Monze Mission Hospital", "MMH", -16.2790, 27.4790, "Monze"}
]

for {name, code, lat, lng, district_name} <- facilities do
  attrs = %{
    name: name,
    code: code,
    latitude: lat,
    longitude: lng,
    district_id: Map.fetch!(district_ids_by_name, district_name)
  }

  case Repo.get_by(Facility, name: name) do
    nil -> {:ok, _facility} = Geography.create_facility(attrs)
    facility -> {:ok, _facility} = Geography.update_facility(facility, attrs)
  end
end

IO.puts("Seeded #{length(districts)} districts and #{length(facilities)} facilities.")
