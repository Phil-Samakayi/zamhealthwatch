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

# Each facility now needs a `code` (Iteration 2: SmsReporting addresses
# a facility by this short code from inside a plain-text SMS, not by
# name or id) and an approximate latitude/longitude too (GIS Mapping -
# town-centre coordinates for the town each facility is actually in,
# not surveyed exact addresses - this is demo seed data for
# MapLive.Index, not authoritative GPS).
#
# Upsert by name, not "skip if the name already exists": a facility
# schema field added after your DB was first seeded (this has already
# happened twice now - `code`, then `latitude`/`longitude`) needs to
# land on the row that's already there, not silently stay nil forever
# because `Repo.get_by(Facility, name: ...)` found something and moved
# on. `mix run priv/repo/seeds.exs` safely backfills new facility
# fields onto existing rows without touching `users` at all - it used
# to mean `mix ecto.reset` instead, which also wipes whichever account
# you're logged in as (see docs/ITERATIONS.md's GIS Mapping entry for
# how that was found).
facilities = [
  {"University Teaching Hospital", "UTH", -15.4067, 28.3229},
  {"Kabwata Clinic", "KBW", -15.4300, 28.2900},
  {"Ndola Teaching Hospital", "NTH", -12.9587, 28.6366},
  {"Monze Mission Hospital", "MMH", -16.2790, 27.4790}
]

for {name, code, lat, lng} <- facilities do
  attrs = %{name: name, code: code, latitude: lat, longitude: lng}

  case Repo.get_by(Facility, name: name) do
    nil -> {:ok, _facility} = Geography.create_facility(attrs)
    facility -> {:ok, _facility} = Geography.update_facility(facility, attrs)
  end
end

IO.puts("Seeded #{length(districts)} districts and #{length(facilities)} facilities.")
