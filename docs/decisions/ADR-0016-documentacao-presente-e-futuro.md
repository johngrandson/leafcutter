# ADR-0016 — Separação documental entre presente, futuro e aberto

- Status: Accepted
- Estado de implementação: MATERIALIZADO

## Contexto

A documentação do Leafcutter descreve uma arquitetura mais ampla que o código atual. Sem uma convenção explícita, diagramas futuros podem ser confundidos com implementação existente, ou removidos durante atualizações incrementais.

## Decisão

Documentos arquiteturais devem distinguir:

```text
MATERIALIZADO
PARCIALMENTE MATERIALIZADO
RATIFICADO — NÃO MATERIALIZADO
ABERTO
PESQUISA
TEMPLATE
```

O documento canônico é `architecture/estado-atual-e-visao-futura.md`.

## Regras

- código e testes definem o estado executável;
- ADR define a decisão, não garante implementação;
- `CURRENT.md` registra o ponto de continuidade;
- arquitetura futura ratificada permanece documentada;
- propostas abertas não são implementadas por inferência;
- research é não normativo.

## Consequências

Toda materialização relevante atualiza o status documental sem apagar os estágios futuros ainda válidos. Review deve detectar tanto documentação que promete código inexistente quanto documentação que perde a visão aprovada.
