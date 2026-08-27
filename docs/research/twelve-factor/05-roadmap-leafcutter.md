# Roadmap Twelve-Factor para o Leafcutter

- Estado: PESQUISA

## Já aderente ou parcialmente aderente

### Codebase e dependencies

Umbrella única, `mix.exs` por app e lockfile compartilhado.

### Backing services

PostgreSQL, PubSub e Oban são explícitos. Repo é authority durável.

### Processes e disposability

RuntimeNode, RunSupervisor, RunCoordinator e RunRecovery tratam processos como reconstruíveis. Ownership não depende de memória local.

### Concurrency

OTP supervision e DynamicSupervisor existem. Data-plane concurrency será Broadway.

### Dev/prod parity

Config compartilhada existe, mas topology de produção ainda não foi materializada.

## Próximos gaps concretos

1. fechar runtime configuration por ambiente;
2. criar release real `:leafcutter`;
3. definir secrets provider;
4. health/readiness;
5. structured logs e metrics backend;
6. migration/deploy sequence;
7. cluster discovery;
8. package inclusion no build;
9. admin process pattern para manutenção;
10. validar graceful shutdown em deployment real.

## Não antecipar

Twelve-Factor não justifica por si só containers, microservices, external queue ou specialized nodes.
