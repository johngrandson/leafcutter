# Plano — spike de conformance HTTP A → B

- Estado: APROVADO
- Natureza: test-only, anterior ao 26C3

## Objetivo

Provar, com dados sintéticos, que as boundaries já materializadas conseguem atravessar uma
página HTTP de uma source até um batch HTTP de uma destination:

~~~text
mock source
→ Read Operation
→ source ContractVersion
→ transformação pura test-only
→ destination ContractVersion
→ Write Operation
→ mock destination
~~~

O spike deve tornar observáveis o envelope HTTP de origem, `Read.Result`, os payloads source e
destination, `Write.Invocation`, o request HTTP de destino e `Write.Result`.

## Estado atual materializado

- `Leafcutter.Catalog.Contracts.compile/1` e `validate/2` compilam e reutilizam validators;
- `LeafcutterConnectors.Operation.Read` e `Write` possuem contracts síncronos;
- `LeafcutterConnectors.Transport.HTTP` executa exatamente uma tentativa bounded;
- a fixture compilada de package prova bindings Read/Write em test;
- `LeafcutterConnectors.TestHTTPServer` fornece um servidor local determinístico.

## Arquitetura futura preservada

- 26C3 continua responsável pela escolha do package de produto e dos sistemas reais;
- autenticação, codecs, paginação, batch e matriz de erros reais continuam abertos;
- Transformation permanece ratificada e não materializada como framework;
- Record, Delivery, Attempt, Checkpoint, Broadway e fan-out durável permanecem posteriores;
- `RunCoordinator`, inventory de produção e RunSnapshot v1 não mudam.

## Decisões abertas

Nenhuma decisão aberta precisa ser fechada para o spike. Toda semântica HTTP implementada é
explicitamente sintética e pertence somente à fixture de teste.

## Owner

~~~text
Context: composição test-only de Catalog Contracts e Connector Operations
OTP application: leafcutter_runtime para o teste; fixture package para Read/Write
Public API/workflow: nenhum novo
~~~

## Mudança mínima

- adicionar um manifest test-only com uma source e uma destination;
- adicionar schemas source/destination e transformação pura à fixture;
- adicionar Read/Write HTTP sintéticos que aceitam URLs via config efêmera de teste;
- compor validators e Operations somente dentro do teste do runtime;
- usar servidor local no gate; Beeceptor ou Mockoon permanecem ferramentas manuais opcionais.

## Failure cases

- payload source viola o ContractVersion e nenhuma chamada destination ocorre;
- destination retorna classificação mista completa e ordenada;
- source retorna `429` com `Retry-After`, normalizado sem retry automático;
- bodies, credentials e vendor payloads não entram em `Operation.Error`.

## Definition of done

- happy path atravessa dois registros e preserva refs/ordem;
- os dois ContractVersions distintos são compilados e aplicados nos pontos ratificados;
- requests HTTP brutos são verificáveis nos mocks;
- failure cases passam de forma determinística e offline;
- `mix format`, testes focados e `mix quality` passam em ambiente com Elixir/PostgreSQL;
- nenhuma mudança em ADR, `CURRENT.md`, inventory de produção ou RunSnapshot v1.
