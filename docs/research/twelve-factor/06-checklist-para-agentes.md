# Checklist Twelve-Factor para agentes

- Estado: PESQUISA / REVIEW AID

## Antes de sugerir mudança

- [ ] O comportamento atual foi verificado no código?
- [ ] O item é requisito do Leafcutter ou preferência genérica Twelve-Factor?
- [ ] A proposta preserva PostgreSQL como authority durável?
- [ ] Config e dependency ficam explícitas?
- [ ] Processo pode ser reconstruído após crash?
- [ ] Shutdown/replay foram considerados?
- [ ] O change exige ADR?

## Build/release/run

- [ ] Build não depende de state local invisível.
- [ ] Release é identificável e reproduzível.
- [ ] Migrations têm sequencing explícito.
- [ ] Runtime config não é compilada acidentalmente quando deveria ser operacional.

## Concurrency

- [ ] OTP/Broadway resolvem a necessidade antes de custom pool.
- [ ] Processos são stateless ou seu estado importante é durável.
- [ ] Scale-out não cria double ownership.
- [ ] Fencing token participa das escritas críticas.

## Backing services

- [ ] PostgreSQL/Oban/PubSub são tratados conforme durabilidade real.
- [ ] PubSub não carrega obrigação durável.
- [ ] External service failure possui contract/retry.

## Documentação

- [ ] A conclusão é marcada como pesquisa, proposta, ratificada ou materializada.
