# Glossário

> **Status: CANÔNICO.** Quando um termo ainda não possui implementação, isso é indicado.

## Materializados

**Organization** — fronteira de tenancy.

**Environment** — scope operacional dentro de uma Organization.

**User** — ator humano do domínio.

**ServiceAccount** — ator não humano pertencente diretamente a uma Organization; credenciais ainda não materializadas.

**Membership** — associação de User a Organization.

**Permission** — primitive tipada de autorização, persistida por identifier estável.

**Role** — agrupamento organization-scoped de Permissions.

**RoleAssignment** — Role concedido a Membership, organization-wide ou environment-scoped.

**ServiceAccountRoleAssignment** — Role concedido diretamente a ServiceAccount.

**RuntimeNode** — uma incarnação específica da application runtime, identificada por UUID.

**Run** — identidade durável de uma execução, com lifecycle mínimo, ownership e uma definição executável congelada nas novas criações públicas.

**RunSnapshot** — definição executável estruturalmente validada, versionada e imutável criada atomicamente com uma nova Run; Runs legadas podem não possuir snapshot.

**Generation** — fencing token monotônico de ownership de Run.

**Ownership token** — `run_id + runtime_node_id + generation`.

**RunRegistry** — Registry local para localizar árvores/processos de Run; não é authority distribuída.

**RunRecovery** — processo de polling que reconcilia ownership durável e árvores locais.

**Connector** — identidade global de um Connector no Catalog; behaviours executáveis pertencem às Operations, e implementações vendor-specific de produto aguardam 26C3.

**ConnectorVersion** — metadata versionada e imutável publicada atomicamente com suas Operations.

**Operation** — ação source ou destination pertencente a uma ConnectorVersion; metadata reside no Catalog e os behaviours Read/Write executáveis residem em `leafcutter_connectors`.

**Transport** — execução de protocolo; o Transport HTTP bounded está materializado.

**Contract** — identidade global de um data contract no Catalog.

**ContractVersion** — versão publicada e imutável de um Contract; novas versões persistem JSON Schema Draft 2020-12 executável, enquanto versões identity-only legadas permanecem históricas.

**Package** — identidade global reutilizável de uma integração no Catalog.

**PackageVersion** — topologia relacional publicada e imutável com exatamente uma source e uma ou mais destinations.

**PackageVersionEndpoint** — endpoint imutável que pinna uma Operation e uma ContractVersion; positions ordenam destinations.

**Integration** — identidade lógica materializada de uma Organization ligada a um Package.

**EnvironmentDeployment** — configuração executável materializada da Integration em um Environment.

## Ratificados para o futuro

**Record** — ocorrência de um item source dentro da Run.

**Delivery** — obrigação durável de processar um Record para um destination.

**Attempt** — tentativa concreta de efeito externo.

**Checkpoint** — último progresso source seguro e durável.

**SourceIdentity** — identidade estável de uma entidade no source.

**PayloadHash** — fingerprint do conteúdo de uma ocorrência.

**IdentityMapping** — relação persistente entre identidades source/destination.

**Transformation** — função pura de negócio.

**Enrichment** — side effect opcional antes da Transformation, com resultado durável.

**Interceptor** — adaptação explícita de request/transport.

**ExecutionEvent** — fato de lifecycle de execução, não event bus genérico.

**AuditEvent** — ação humana/administrativa append-only.

## Termos a evitar

**Exactly-once universal** — promessa não feita pelo sistema.

**Distributed Registry como ownership** — incorreto; PostgreSQL é authority.

**Context = tabela** — incorreto; context é boundary de domínio.
