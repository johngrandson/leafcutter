# Capacidades do produto Leafcutter

## Foundations disponíveis

### Tenancy e access control

- Organizations e Environments;
- Users, Memberships e ServiceAccounts;
- Roles e permissions;
- assignments organization/environment-scoped;
- authorization para User e ServiceAccount.

### Runtime control plane

- identity/liveness de runtime nodes;
- Run lifecycle mínimo;
- ownership e generation fencing;
- criação atômica de Run + RunSnapshot v1;
- per-Run supervision;
- automatic recovery de Runs `running` e `pending` elegíveis;
- concorrência distribuída baseada em PostgreSQL.

### Plataforma

- umbrella boundaries;
- Repo/PubSub/Oban compartilhados;
- Phoenix API foundation;
- quality gates e harness.

## Capacidades ratificadas em desenvolvimento futuro

### Core de integração

- Catalog;
- Contracts JSON Schema;
- Connector/Operation/Transport;
- Integration Packages;
- Connections e Secrets;
- Integrations e EnvironmentDeployments;

### Data plane

- one Source → N Destinations;
- pagination;
- validation nas duas bordas;
- Transformation 1→0/1/N;
- optional Enrichment;
- batching/backpressure Broadway;
- partial batch success;
- retries/rate limits;
- durable Record/Delivery fan-out;
- Checkpoint e Attempts;
- IdentityMapping;
- execution monitoring.

### Governance

- User/ServiceAccount authentication;
- homologation;
- promotion/rollback;
- payload access permissions;
- secret rotation;
- AuditEvents e Notifications.

## Futuro condicionado por demanda

- Inbound API;
- API Management;
- multi-transport;
- package isolation;
- object storage/analytics;
- specialized nodes;
- external queue;
- multi-source joins;
- SDKs após API estabilizada.
