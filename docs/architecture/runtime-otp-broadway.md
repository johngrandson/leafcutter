# Runtime OTP e Broadway

## Princípio

```text
OTP control plane
→ lifecycle e coordenação

Broadway data plane
→ fluxo, demand, concorrência, batching e backpressure
```

## Foundation OTP inicial

A infraestrutura mínima do runtime começa com três processos supervisionados:

```text
LeafcutterRuntime.Application
├── LeafcutterRuntime.RunRegistry
├── LeafcutterRuntime.RunDynamicSupervisor
└── LeafcutterRuntime.NodeHeartbeat
```

`RunRegistry` é um `Registry` local com chaves `:unique`. Ele fornece identidade
operacional dentro do node e não representa ownership distribuído.

`RunDynamicSupervisor` começa vazio e somente receberá árvores de Run depois que
ownership, generation/fencing e lifecycle durável estiverem materializados.

## Liveness durável de runtime nodes

Cada inicialização da application `leafcutter_runtime` gera um UUID que representa
uma incarnação específica do runtime:

```text
application start
→ runtime_node_id novo

NodeHeartbeat restart
→ preserva runtime_node_id

application / BEAM restart
→ runtime_node_id novo
```

A persistência pertence ao Context `Executions`:

```text
LeafcutterRuntime.NodeHeartbeat
        ↓
Leafcutter.Executions.Nodes.heartbeat/2
        ↓
runtime_nodes
```

`runtime_nodes` armazena:

```text
id
node_name
last_heartbeat_at
inserted_at
updated_at
```

`id` é a identidade da incarnação. `node_name` registra `node()` apenas como
metadata e deliberadamente não é único. Uma nova incarnação pode reutilizar o
mesmo nome sem reviver ownership pertencente a um processo antigo.

O heartbeat segue esta ordem:

```text
persistir last_heartbeat_at no PostgreSQL
→ emitir Telemetry efêmero
→ agendar próxima tentativa
```

Evento mantido:

```text
[:leafcutter, :runtime, :node, :heartbeat]
```

Falhas temporárias de persistência são registradas e tentadas novamente no próximo
intervalo sem colocar o `NodeHeartbeat` em crash loop. O heartbeat ainda não concede,
renova ou recupera ownership de Run; essa responsabilidade entra com `owner_node_id`
e `generation`.

## Run supervision tree

```text
RunDynamicSupervisor
└── RunSupervisor <run_id>
    ├── RunCoordinator
    ├── SourceBroadway
    ├── optional EnrichmentBroadways
    └── DestinationBroadways
        ├── Destination B
        └── Destination C
```

Broadway já é uma supervision tree. Não duplicar SourceRuntime/DestinationRuntime se a própria pipeline representa corretamente lifecycle e estado.

## RunCoordinator

Deve permanecer fora do data path.

Recebe apenas comandos e eventos grossos:

```text
start
pause
resume
cancel
source_completed
destination_completed
run_failed
```

Não recebe uma mensagem por Record.

## Source Broadway

```text
Read Operation Producer
    ↓
source contract validation
    ↓
source identity + payload hash
    ↓
persistence batch
    ↓
transaction:
  Records
  N Deliveries per Record
  Checkpoint
```

Checkpoint avança somente após commit do durable fan-out.

## Destination Broadway

Uma pipeline independente por destination:

```text
Postgres Delivery Producer
    ↓ claim available Deliveries
prepare_messages/load in batch
    ↓
Transformation
    ↓
destination contract validation
    ↓
Broadway batcher
    ↓
Write Operation
    ↓
Attempt + Delivery outcome
```

Um destination lento não bloqueia os demais. Seu backlog cresce de forma independente até atingir limites de storage/operacionais.

## Claim de Deliveries

O Producer usa transações curtas e claim atômico, por exemplo com `FOR UPDATE SKIP LOCKED` ou mecanismo equivalente.

Locks não permanecem abertos durante requests externas.

## Acknowledger

O Acknowledger do Broadway pode fechar o ciclo de sucesso/falha da mensagem. A persistência de Attempt/Delivery deve continuar explícita e testável.

## Retry

Broadway não é o scheduler de retry. Delivery retryable retorna a:

```text
status = pending
available_at = future timestamp
attempt_count += 1
```

O Producer só busca itens disponíveis.

Oban não precisa representar cada Delivery. Continua voltado a schedules, notifications, maintenance e trabalhos duráveis de menor cardinalidade.

## Pausa e cancelamento

O desenho concreto de pause/resume/cancel será definido na implementação do runtime. A regra é persistir a intenção e fazer a árvore convergir, sem depender somente de mensagens efêmeras.
