# Protocolo de mudança

## Mudança de código sem alteração arquitetural

1. confirmar owner e contract atual;
2. implementar menor diff;
3. testar;
4. atualizar docs in-code;
5. executar quality gates.

## Materialização de arquitetura já ratificada

1. confirmar ADR e specification;
2. implementar slice;
3. atualizar estado de implementação no ADR/index;
4. mover a capacidade de futura para materializada nos docs;
5. preservar os estágios futuros restantes;
6. atualizar `CURRENT.md`.

## Nova decisão arquitetural

1. registrar contexto e alternativas;
2. obter ratificação;
3. criar/atualizar ADR;
4. atualizar arquitetura/specification;
5. somente então implementar.

## Mudança de direção

Não apagar histórico. Criar ADR superseding ou documentar evolução explícita.

## Proibição

Não usar documentação para declarar concluído o que não passa nos testes/gates.
