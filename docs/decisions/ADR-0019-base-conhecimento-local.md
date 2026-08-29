# ADR-0019 — Base de conhecimento local derivada

- Status: Accepted
- Estado de implementação: NÃO MATERIALIZADO

## Contexto

O Leafcutter precisa acumular sínteses, gotchas e correções humanas sem
rederivar esse conhecimento em cada sessão. A nova camada não pode criar
uma fonte de autoridade paralela nem um contrato exclusivo de uma ferramenta.

## Decisão

A base em `docs/knowledge/` é derivada e não normativa. Cada claim ativo
referencia sua autoridade. `AGENTS.md` define o contrato compartilhado e
skills específicos apenas adaptam esse contrato a cada ferramenta.

Fontes humanas em `raw/` são imutáveis. Conteúdo produzido por agentes nasce
em `proposals/` e só entra na base ativa após aprovação. Consultas e lint não
alteram arquivos. Pins provocam reconciliação, nunca sobrepõem código, testes,
ADRs, specifications ou `CURRENT.md`.

## Consequências

- o desenvolvedor continua autor principal;
- conflitos retornam à fonte canônica;
- o roteamento segue contexts do Leafcutter;
- nenhuma infraestrutura de busca entra no primeiro slice;
- a base possui lint determinístico antes do merge.
