# Roadmap Twelve-Factor para o Leafcutter

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## Roadmap alinhado ao estado atual

Este roadmap ordena trabalho, mas não autoriza implementá-lo antes dos gates do
checkpoint. Em especial, nenhuma application, schema ou migration deve nascer
durante a ratificação de `Executions`.

### Etapa 0. Terminar o Context Map

Pré-requisito atual: nenhum.

Trabalho:

1. Ratificar a responsabilidade exata de `Executions`.
2. Ratificar `Notifications` e `Audit`.
3. Revisar ownership conjunto, APIs públicas e dependências.

Como o Twelve-Factor ajuda nesta etapa:

- `Executions` deve possuir verdade durável de Run sem transformar PID ou
  memória local em autoridade;
- `Notifications` precisa de obrigação durável, não apenas PubSub;
- `Audit` continua sink durável e não log operacional;
- nenhuma dessas conclusões define tabela, processo ou app OTP antecipadamente.

Evidência de conclusão: `CURRENT.md` e o Context Map marcam todos os contexts
como ratificados. Não há mudança de código.

### Etapa 1. Ratificar as boundaries das OTP applications

Pré-requisito: Context Map completo.

Decisões necessárias:

- confirmar se a unidade inicial de deploy é uma única release homogênea;
- fechar o grafo entre core, connectors, runtime e API;
- decidir ownership de Repo, migrations, PubSub e Oban;
- definir quais behaviours precisam atravessar boundaries de apps;
- manter `packages/` fora dos internals do runtime e da API.

Saída Twelve-Factor esperada: um pequeno documento de contrato app/plataforma
que declare codebase, unidade de build, unidade de release e tipos de processo.
Esse documento pode virar ADR apenas depois de discussão e ratificação.

Evidência de conclusão: grafo aceito, sem ciclos, refletido em `CURRENT.md`.

### Etapa 2. Fechar o contrato de build e configuração da Foundation

Pré-requisito: boundaries das apps ratificadas.

Entregáveis de desenho:

- versões suportadas de Erlang/OTP e Elixir;
- build target e dependências de sistema;
- esquema de release ID e relação com commit;
- taxonomia de build-time versus runtime config;
- catálogo inicial de env vars e resource handles;
- comportamento de boot diante de config inválida;
- estratégia inicial para compilar Integration Packages na release;
- comando de migration/one-off e sequência de deploy;
- decisão de port binding e health/readiness;
- contrato mínimo de logs e redaction.

Não é necessário escolher fila externa, Redis, object storage, roles separados ou
Kubernetes. O provider pode continuar aberto se o contrato não depender dele.

Evidência de conclusão: decisões ratificadas e critérios de aceitação anexados
ao primeiro marco. Ainda não se deve declarar conformidade operacional.

### Etapa 3. Criar a primeira release mínima

Pré-requisito: Etapa 2 e autorização de implementação.

Incrementos sugeridos:

1. Criar somente as OTP applications aprovadas, com supervision trees reais.
2. Fixar toolchain e declarar dependencies por app.
3. Adicionar CI para `mix quality`.
4. Produzir uma release Mix imutável com ID inspecionável.
5. Ler config de deploy no boot e validar valores obrigatórios.
6. Subir o Endpoint aprovado por port binding.
7. Emitir logs na saída padrão com redaction mínima.
8. Disponibilizar health/readiness com semântica testada.
9. Executar uma tarefa one-off versionada na mesma release.

Verificações:

- build em ambiente limpo;
- boot sem checkout e sem Mix no target;
- falha clara para config ausente;
- mesmo artefato iniciado com duas configurações não sensíveis distintas;
- SIGTERM encerra a application tree;
- logs não criam arquivo local nem expõem secret;
- CI executa formatter, compiler, Credo, testes e Dialyzer.

Essa etapa cobre a Foundation do
[roadmap arquitetural](../../architecture/roadmap.md) e o
[primeiro marco](../../implementation/first-milestone.md).

### Etapa 4. Provar os fatores no vertical slice V1

Pré-requisito: release mínima e contexts básicos implementados.

Trabalho:

- usar PostgreSQL do mesmo tipo e versão em desenvolvimento, CI, homologação e
  produção;
- persistir Run Snapshot e provenance da release;
- construir fan-out durável dentro de transação;
- provar restart de Source e Destination Broadway;
- provar replay `at-least-once` e idempotency quando suportada;
- tratar Connections como recursos configurados, sem credencial no código;
- validar que ContractVersions e PackageVersions são congeladas antes do run;
- expor o workflow administrativo pelo Endpoint da release.

Evidência de conclusão: testes de crash/restart, atomicidade, concorrência e
contrato, além de um deploy de homologação usando o artefato que poderá ser
promovido.

### Etapa 5. Endurecer operação em V1.x

Pré-requisito: V1 funcional e métricas reais.

Trabalho:

- definir e testar graceful shutdown de API, Oban e Broadways;
- estabelecer startup e readiness budgets;
- testar rolling deploy e recovery de node;
- completar logs estruturados, metrics, traces, alertas e correlação;
- testar troca e restore de backing resources;
- automatizar migrations e rollback compatível;
- definir secret provider, rotation e redaction;
- medir pool, backlog, throughput, storage e fairness.

Fila externa, node roles especializados e stores adicionais só entram se as
métricas confirmarem os gargalos previstos no roadmap.

### Etapa 6. Reavaliar a cada mudança de unidade de deploy

Gatilhos para nova avaliação:

- API e runtime passam a releases independentes;
- Integration Packages viram artefatos carregados fora da release;
- aparece uma fila externa;
- object storage passa a guardar payloads;
- nodes ganham roles diferentes;
- a versão revisada do manifesto Twelve-Factor é oficialmente publicada.

Cada gatilho pode mudar codebase, dependencies, config, backing services,
process formation e release lifecycle. A resposta não deve ser copiar esta
avaliação. O agente precisa observar a implementação e atualizar a conclusão.

## Conclusão

O Twelve-Factor oferece ao Leafcutter uma boa lista de perguntas sobre a borda
operacional da aplicação. Ele é particularmente valioso porque a documentação
local está forte no domínio e no runtime, mas ainda não fechou como um commit se
torna uma release configurada, observável, reiniciável e administrável.

O melhor uso agora é como restrição de planejamento. A ratificação de
`Executions` deve preservar estado durável e runtime reconstruível. A
ratificação das OTP applications deve declarar a unidade real de deploy. Depois,
a Foundation deve fechar config, build, release, porta, logs e one-offs antes de
prometer portabilidade ou operação em cluster.

Não há motivo para adicionar containers, Kubernetes, filas ou abstrações
genéricas por causa desta pesquisa. Uma release Mix única, Postgres como recurso
durável, nodes homogêneos e contratos pequenos podem atender bem aos princípios
originais. O trabalho difícil é provar o comportamento em boot, crash, deploy e
recovery. Essa prova virá de artefatos e testes, não de uma etiqueta
"Twelve-Factor".
