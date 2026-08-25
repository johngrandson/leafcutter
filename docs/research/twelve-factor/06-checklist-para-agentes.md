# Backlog e checklist Twelve-Factor para agentes

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## Backlog orientado a evidências para agentes

As tarefas abaixo são futuras. O campo "quando" é um gate, não uma sugestão para
começar imediatamente.

| ID | Quando | Tarefa | Evidência de aceitação | Fatores |
|---|---|---|---|---|
| TF-01 | Após Context Map | Definir a unidade inicial de app/deploy | ADR ou decisão ratificada, grafo sem ciclos e `CURRENT.md` atualizado | I, V, VIII |
| TF-02 | Após apps ratificadas | Versionar toolchain e inventariar dependencies de sistema | Build limpo documentado, versões fixadas, nenhum executável implícito | II, X |
| TF-03 | Antes da primeira release | Classificar config de build, deploy, domínio e secrets | Catálogo com owner, fonte, validação e redaction | III, IV |
| TF-04 | Antes da primeira release | Definir artifact/release ID e provenance | Release aponta para commit e digest; Run pode registrar release version | I, V |
| TF-05 | Na criação da API | Definir port binding e probes | Endpoint autocontido, porta configurável, health/readiness testados | VII, IX |
| TF-06 | Na criação do Repo | Definir migration e one-off lifecycle | Comando da release, mesma config, execução repetível e falha observável | V, XII |
| TF-07 | No primeiro runtime | Escrever crash matrix | Testes cobrem processo, node, pre/post-commit e stale generation | VI, IX |
| TF-08 | Antes do primeiro deploy | Definir logging contract | `stdout`/`stderr`, metadata, níveis, redaction e captura externa | XI |
| TF-09 | Antes de produção | Definir parity matrix | Toolchain e backing service type/version comparados por ambiente | X |
| TF-10 | Em V1.x | Provar graceful shutdown | SIGTERM, drain, reclaim e rolling deploy passam em teste | IX |
| TF-11 | Em V1.x | Validar resource replacement e restore | Troca de handle e restore ensaiados sem mudança de código | IV, X |
| TF-12 | Após métricas | Reavaliar process formation | Decisão baseada em throughput, backlog, DB pool e isolamento medidos | VIII |

## Checklist para uma futura revisão

Um agente que revisar o Leafcutter contra o Twelve-Factor deve responder com
evidência, não com a intenção do documento:

### Codebase e build

- Qual commit gerou o artefato?
- O build começa em ambiente limpo e usa apenas dependencies declaradas?
- A release tem ID único e é imutável?
- O runtime baixa ou compila algo que deveria ter sido resolvido no build?

### Config e recursos

- O que varia por deploy e de onde cada valor vem?
- Config inválida impede boot com erro seguro?
- Config de tenant continua no context proprietário?
- Backing service pode ser substituído por handle sem editar código?
- Secrets aparecem em logs, manifests, Run Snapshots públicos ou erros?

### Runtime

- Que estado se perde quando a BEAM morre?
- O Postgres contém informação suficiente para reconstruir cada obrigação?
- Duas instâncias podem executar trabalho concorrente sem stale owner gravar?
- A aplicação escala para N nodes sem sticky session ou filesystem compartilhado?

### Deploy e operação

- O mesmo artefato atravessa homologação e produção?
- A API escuta uma porta configurável e tem readiness honesta?
- SIGTERM e SIGKILL preservam as invariantes duráveis?
- Logs vão para streams e não substituem AuditEvent ou ExecutionEvent?
- Migrations e one-offs usam a mesma release e config?

### Limites da conclusão

- A avaliação distingue código observado, decisão ratificada e proposta?
- O fator está sendo usado fora de seu escopo?
- A recomendação cria infraestrutura antes de existir uma necessidade medida?
- O checkpoint autoriza essa etapa?
