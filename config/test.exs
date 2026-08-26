import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :leafcutter_api, LeafcutterApi.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TGk2ucReWoiV44vdR42p2UGkv/ya8Eac+sbiwkiFv3vIMkOYW+a4noWnOGuj2+LX",
  server: false
