# Storage e retenção

## Modelo lógico e armazenamento físico

O modelo lógico permanece:

```text
Run
└── Record
    ├── Enrichment
    └── Delivery
        └── Attempt
```

Isso não obriga todos os payloads a permanecer no Postgres quente para sempre.

## Metadata vs content

```text
Queryable metadata
→ status, timestamps, identity, hashes, errors, indexes

Audit content
→ source payload, transformed payload, request, response
```

## Primeira versão

Começar simples com PostgreSQL, inclusive JSONB quando útil, mas manter campos/ref abstraídos para futura migração de conteúdo volumoso.

## Evolução

```text
PostgreSQL
→ operational truth and queryable metadata

Object Storage
→ large immutable payloads and archived bodies

Analytics Store future
→ large-scale historical aggregation
```

Object storage é preferível a introduzir um segundo banco operacional apenas para frio.

## Payload references

Quando externalizado:

```text
payload_ref
payload_sha256
content_type
size
retention_class
```

Hashes ajudam integridade e deduplicação futura.

## Retenção

Policies podem ser environment/plan scoped:

```text
hot
warm
cold
expired/deleted
```

Audit export pode ser assíncrono e possuir SLA próprio, executado por Oban.

## Queries

Frontend/API comum usa:

- summaries;
- filtros;
- paginação;
- individual Record/Delivery/Attempt.

Nunca carrega a coleção completa de milhões de Records.

## PII e secrets

Payload access precisa de permissão própria. Secrets nunca são persistidos em audit payloads. Redaction deve ser aplicada antes de logs e eventos.
