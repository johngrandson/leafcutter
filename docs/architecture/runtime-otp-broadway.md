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

`RunDynamicSupervisor` recebe somente árvores de Run que já possuem ownership
durável. Ele não faz claim, recovery distribuído ou decisão de fencing.

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
obter timestamp do PostgreSQL
→ persistir last_heartbeat_at
→ emitir Telemetry efêmero
→ agendar próxima tentativa
```

Evento mantido:

```text
[:leafcutter, :runtime, :node, :heartbeat]
```

Falhas temporárias de persistência são registradas e tentadas novamente no próximo
intervalo sem colocar o `NodeHeartbeat` em crash loop.

## Ownership durável e fencing de Run

O primeiro schema de `Run` materializa somente lifecycle e authority de ownership:

```text
Run
├── status
├── owner_node_id
├── generation
└── ownership_acquired_at
```

Estados iniciais:

```text
pending
running
completed
failed
cancelled
```

Somente `pending` e `running` são claimable. O primeiro claim muda `pending` para
`running`. Estados terminais não podem receber ownership novo.

`owner_node_id` referencia uma incarnação específica em `runtime_nodes`. A
expiração usa um threshold inicial de 45 segundos e compara
`runtime_nodes.last_heartbeat_at` com o relógio do PostgreSQL. O relógio local da
máquina não participa da decisão distribuída de liveness.

Claim é serializado por row lock na própria Run:

```text
transaction
↓
SELECT Run FOR UPDATE
↓
validar claimant RuntimeNode ativo
↓
avaliar owner atual
```

Semântica:

```text
Run sem owner
→ atribui claimant
→ generation + 1

owner expirado
→ substitui owner
→ generation + 1

mesmo owner ativo
→ retorna o token atual
→ não incrementa generation

outro owner ativo
→ rejeita claim
```

O resultado de claim é um fencing token:

```text
run_id
runtime_node_id
generation
```

Release aplica o token na mesma instrução SQL que remove ownership:

```sql
WHERE run_id = :run_id
  AND owner_node_id = :runtime_node_id
  AND generation = :generation
```

Release preserva status e generation. Uma segunda release do mesmo token é
idempotente enquanto não existir claim posterior. Depois que outro node incrementa
`generation`, o token antigo é rejeitado como stale.

Não criar uma operação separada de `verify_ownership` antes de uma escrita. Toda
mutação crítica futura deve incluir `owner_node_id + generation` no mesmo comando SQL
que altera o estado, evitando uma race entre verificação e persistência.

A criação pública de Run continua adiada até que definição executável e RunSnapshot
estejam ratificadas. Recovery scanning e Broadway permanecem fora deste recorte.

## Foundation de supervisão por Run

O primeiro workflow operacional é:

```text
LeafcutterRuntime.Runs.start(run_id)
↓
Executions.Runs.claim(run_id, runtime_node_id)
↓
RunDynamicSupervisor.start_child(...)
↓
RunSupervisor <run_id>
└── RunCoordinator
```

Claim sempre acontece antes do startup local. Repetir `start/1` para a mesma
generation retorna o mesmo `RunSupervisor`. Se uma generation local antiga ainda
estiver registrada depois de um novo claim, a árvore antiga é encerrada antes que a
nova seja iniciada.

O `RunSupervisor` registra:

```text
RunRegistry key
→ run_id

RunRegistry value
→ ownership_token
```

O `RunCoordinator` usa uma chave local separada:

```text
{:coordinator, run_id}
```

O token completo permanece disponível como Registry metadata. O Registry é apenas
uma visão local e nunca substitui o estado em PostgreSQL.

O `RunSupervisor` é um child `:transient` do `RunDynamicSupervisor`. Seu
`RunCoordinator` também é `:transient`, mas é marcado como significativo. A
supervision tree usa automatic shutdown:

```text
RunCoordinator crash anormal
→ coordinator reiniciado
→ RunSupervisor permanece

RunCoordinator exit normal por stale ownership
→ RunSupervisor encerra toda a árvore
→ DynamicSupervisor não reinicia a generation stale
```

`LeafcutterRuntime.Runs.stop/1` tenta release durável e depois encerra a árvore
local. Mesmo quando release informa `:stale_ownership`, o processo local é removido
para convergir com a authority atual.

Quando uma escrita crítica futura retornar `:stale_ownership`, o caller deve enviar
o token rejeitado para:

```text
LeafcutterRuntime.Runs.stale_ownership(ownership_token)
```

A comparação usa o token completo. Um evento atrasado de uma generation antiga não
pode encerrar uma árvore local mais nova. O token stale não é liberado porque outro
owner pode já ser o atual.

Este recorte ainda não adiciona:

```text
recovery scanner
RunSnapshot
pause/resume
terminalização coordenada
SourceBroadway
DestinationBroadway
Record/Delivery processing
```

## Run supervision tree

Forma atual:

```text
RunDynamicSupervisor
└── RunSupervisor <run_id>
    └── RunCoordinator
```

Forma futura:

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

Broadway já é uma supervision tree. Não duplicar SourceRuntime/DestinationRuntime se
a própria pipeline representa corretamente lifecycle e estado.

## RunCoordinator

Deve permanecer fora do data path.

A responsabilidade atual é reter o ownership token e convergir a árvore quando o
token é rejeitado como stale. Comandos e eventos grossos futuros incluem:

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

Um destination lento não bloqueia os demais. Seu backlog cresce de forma independente
até atingir limites de storage/operacionais.

## Claim de Deliveries

O Producer usa transações curtas e claim atômico, por exemplo com
`FOR UPDATE SKIP LOCKED` ou mecanismo equivalente.

Locks não permanecem abertos durante requests externas.

## Acknowledger

O Acknowledger do Broadway pode fechar o ciclo de sucesso/falha da mensagem. A
persistência de Attempt/Delivery deve continuar explícita e testável.

## Retry

Broadway não é o scheduler de retry. Delivery retryable retorna a:

```text
status = pending
available_at = future timestamp
attempt_count += 1
```

O Producer só busca itens disponíveis.

Oban não precisa representar cada Delivery. Continua voltado a schedules,
notifications, maintenance e trabalhos duráveis de menor cardinalidade.

## Pausa e cancelamento

O desenho concreto de pause/resume/cancel será definido na implementação do runtime.
A regra é persistir a intenção e fazer a árvore convergir, sem depender somente de
mensagens efêmeras.
