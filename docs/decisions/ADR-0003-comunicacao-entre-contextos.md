# ADR-0003 - Comunicação entre contexts

- Status: Accepted

## Decisão

```text
precisa de resposta
→ chamada direta à API pública

fato efêmero já ocorrido
→ Phoenix.PubSub

obrigação assíncrona que deve sobreviver
→ persistência + Oban
```

PubSub nunca é fonte da verdade. Contexts não acessam internals uns dos outros.

## Consequências

- fluxo principal rastreável;
- efeitos secundários desacoplados;
- sem event bus genérico;
- eventos duráveis exigem persistência explícita.
