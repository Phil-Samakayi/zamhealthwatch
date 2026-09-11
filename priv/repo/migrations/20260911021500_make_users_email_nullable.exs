defmodule ZamHealthWatch.Repo.Migrations.MakeUsersEmailNullable do
  use Ecto.Migration

  @moduledoc """
  An SMS-only reporter (`Accounts.find_or_create_sms_reporter/1`) is a
  real `User` with no email - `phx.gen.auth`'s original migration made
  `email` `null: false`, an assumption that held until this iteration
  added a second way to become a user. The unique index on `email`
  still applies to any user that does have one; Postgres allows
  multiple `NULL`s under a unique index by default, so several
  email-less SMS reporters don't collide with each other.
  """

  def change do
    alter table(:users) do
      modify :email, :citext, null: true
    end
  end
end
