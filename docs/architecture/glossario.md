# Glossário oficial

## Catalog

Registro de building blocks reutilizáveis: Connectors, Operations, Contracts e Package Versions.

## Connector

Conhecimento compartilhado sobre como um sistema externo funciona.

## Operation

Ação reutilizável de leitura ou escrita executada através de um Connector.

## Transport

Implementação de protocolo, inicialmente HTTP.

## Connection

Configuração concreta e environment-scoped de acesso a um sistema externo.

## Secret

Valores sensíveis versionados usados por uma Connection.

## Contract

JSON Schema versionado que define a estrutura válida de um payload.

## Integration Package

Artefato versionado com manifest, contracts e código específico de integração.

## Integration

Instância configurada de um Package para uma Organization + Environment.

## Trigger / Schedule

Mecanismo que inicia um Run.

## Run

Execução concreta e imutável de uma Integration.

## Run Snapshot

Configuração efetiva congelada no início do Run.

## Record

Ocorrência de um item de origem dentro de um Run.

## Source Identity

Identidade estável da entidade no sistema de origem.

## Payload Hash

Fingerprint do conteúdo atual do Record.

## Delivery

Obrigação durável de processar um Record para um destination.

## Attempt

Tentativa técnica concreta de uma Operation externa.

## Destination Identity

ID retornado/extraído no sistema de destino.

## IdentityMapping

Relação entre Source Identity e Destination Identity.

## Transformation

Função Elixir pura que converte payload de origem em payload(s) de destino.

## Enrichment

Consulta externa opcional e durável realizada antes da Transformation.

## Interceptor

Hook explícito de transporte para headers, query, URL, signing ou tracing metadata.

## ExecutionEvent

Fato relevante do lifecycle de execução.

## AuditEvent

Registro de ação humana ou administrativa.

## Environment

Escopo operacional isolado dentro de uma Organization.

## Homologation

Processo de validação/aprovação de uma Package Version/configuração antes da promoção.

## Promotion

Ativação de uma versão aprovada em um target Environment sem copiar secrets.
