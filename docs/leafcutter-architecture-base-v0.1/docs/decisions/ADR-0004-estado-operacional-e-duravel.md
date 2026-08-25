# ADR-0004 - Estado operacional e estado durável

- Status: Accepted

## Decisão

OTP/Broadway mantém estado operacional de alta frequência. PostgreSQL mantém estado recuperável, histórico, ownership, checkpoints e intenções.

Processos são reconstruíveis. Supervisor reinicia processos; Postgres explica de onde continuar.

## Consequências

- recovery após crash de processo ou node;
- replay esperado;
- necessidade de checkpoints explícitos;
- proibição de usar GenServer como banco.
