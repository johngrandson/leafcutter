# Runtime OTP e Broadway

## Princípio

```text
OTP control plane
→ lifecycle e coordenação

Broadway data plane
→ fluxo, demand, concorrência, batching e backpressure
```

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
