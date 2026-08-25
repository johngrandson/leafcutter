# Modelo conceitual

## Relação principal

```text
Package Version
    │ configured as
    ▼
Integration
    │ executed as
    ▼
Run
    │ processes
    ▼
Record
    │ fans out into
    ▼
Delivery
    │ attempted through
    ▼
Attempt
```

## Organization e Environment

`Organization` é a fronteira de propriedade de um cliente. `Environment` isola configuração e operação, por exemplo `development`, `homologation` e `production`.

Connections, Integrations, Runs e IdentityMappings são environment-scoped quando o isolamento for necessário.

## Catalog

O Catalog organiza building blocks reutilizáveis:

- Official Connectors;
- Custom Connectors reutilizáveis;
- Operations;
- Contracts e suas versões;
- Integration Packages e suas versões;
- categorias e metadata de descoberta.

## Integration Package

O Package é código e metadata versionados. Ele não guarda secrets nem configuração concreta de cliente.

```text
Package
├── source definition
├── destination definitions
├── contracts
├── transformations
├── enrichments
├── interceptors
└── dependency versions
```

## Integration

A Integration é uma instância configurada do Package dentro de um Organization + Environment.

Ela escolhe:

- Package Version;
- Connections;
- valores de configuração;
- batching e concorrência permitidos;
- Trigger/Schedule;
- Labels;
- estado ativo/inativo.

## Run Snapshot

Quando um Run começa, a configuração efetiva é congelada:

```text
Package defaults
+ Integration overrides
+ resolved Contract versions
+ resolved dependency versions
+ Connection references
= immutable Run Snapshot
```

Mudanças posteriores na Integration não alteram Runs já iniciados.

## Record, Delivery e Attempt

```text
Record
→ ocorrência de um item da origem dentro de um Run

Delivery
→ obrigação durável de processar esse Record para um destino

Attempt
→ tentativa concreta de executar uma operação externa
```

## Identity

```text
Record ID
→ ocorrência interna

Source Identity
→ identidade estável no sistema de origem

Payload Hash
→ fingerprint do conteúdo daquela versão

IdentityMapping
→ relação entre uma Source Identity e uma Destination Identity
```

## Enrichment

Enrichment é trabalho opcional e durável para buscar dados adicionais antes da Transformation. Side effects pertencem a Connector/Operation; a Transformation permanece pura.

## Eventos

```text
ExecutionEvent
→ fatos relevantes do lifecycle de um Run

AuditEvent
→ ação humana ou administrativa

PubSub message
→ sinal efêmero, nunca fonte da verdade
```
