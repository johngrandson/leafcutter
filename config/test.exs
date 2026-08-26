import Config

config :logger, level: :warning

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :leafcutter_api, LeafcutterApi.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TGk2ucReWoiV44vdR42p2UGkv/ya8Eac+sbiwkiFv3vIMkOYW+a4noWnOGuj2+LX",
  server: false

config :leafcutter_core, Leafcutter.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "leafcutter_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :leafcutter_core, Oban, testing: :manual

config :leafcutter_runtime, LeafcutterRuntime.NodeHeartbeat, interval: 50
