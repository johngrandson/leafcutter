defmodule Leafcutter.Repo do
  use Ecto.Repo,
    otp_app: :leafcutter_core,
    adapter: Ecto.Adapters.Postgres
end
