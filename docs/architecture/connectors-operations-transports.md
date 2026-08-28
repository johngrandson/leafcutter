# Connectors, Operations e Transports

> **Status: PARCIALMENTE MATERIALIZADO.** Connector, ConnectorVersion e Operation existem como metadata no Catalog; os contracts executáveis em `leafcutter_connectors` e Transport permanecem futuros.

## Estado materializado

```text
Connector
└── immutable ConnectorVersion
    └── Operation metadata
```

`Leafcutter.Catalog.Connectors` cria e lê Connector identities e publica ConnectorVersion com suas Operations atomicamente. Operation materializa `ref` e `role: source | destination`; behaviour executável, paginação, requests, responses e Transport não fazem parte desse slice.

## Separação

```text
Connector
→ conhece o sistema externo

Operation
→ conhece uma ação específica

Transport
→ conhece o protocolo
```

Catalog possui metadata e versões. `leafcutter_connectors` possuirá behaviours e implementações executáveis.

## Connector

Responsabilidades planejadas:

- conventions do sistema externo;
- autenticação suportada;
- headers e erros comuns;
- rate-limit metadata;
- Operations disponíveis.

Não conhece Organization, Integration específica ou Transformation de Package.

## Read Operation

Normalizará paginação para um contract independente de `page`, `offset`, cursor ou `next_url`.

Resultado conceitual:

```text
records
next_cursor
done?
metadata
```

## Write Operation

Receberá batch já transformado e validado e preservará resultado por item, inclusive sucesso parcial.

## Transport

HTTP será o primeiro Transport. Database, SFTP e outros só entram com demanda real.

## Error taxonomy ratificada

```text
validation
authentication
rate_limited
timeout
temporary
permanent
```

A forma exata dos tipos e structs ainda será fechada na implementação.

## Restrições

- não criar GenServer por Connector sem lifecycle real;
- não esconder Transformation dentro da Operation;
- não persistir secrets em Connector metadata;
- não acoplar runtime genérico a detalhes de HTTP;
- não implementar múltiplos transports por antecipação.
