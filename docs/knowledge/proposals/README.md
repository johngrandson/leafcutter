---
type: proposals
updated: 2026-08-29
---
# Propostas de conhecimento

Este diretório contém candidatos persistidos e não ativos. Eles não alteram o
roteamento, não participam da consulta normal e não estabelecem authority.

## Formato

Cada candidato ocupa um único arquivo cujo nome repete seu `entry_id`, como
`docs/knowledge/proposals/G-capture-format.md`, com exatamente este
frontmatter:

```yaml
type: proposal
entry_id: G-capture-format
target: docs/knowledge/gotchas.md
updated: 2026-08-29
```

O `target` é exatamente `docs/knowledge/gotchas.md`,
`docs/knowledge/pins.md` ou `docs/knowledge/syntheses.md`. O `entry_id` usa o
prefixo do tipo de destino: `G-`, `PIN-` ou `SYN-`. O corpo contém um único
bloco cercado `markdown` com a entrada candidata completa no schema Markdown
exato da coleção ativa escolhida, com todos os campos exigidos. Consulte
`../README.md` para os schemas ativos; ele nunca é um target.

## Ciclo de vida

Pedido explícito para captura autoriza criar ou atualizar somente o arquivo de
proposta. O agente lê schema e fonte canônica, prepara o candidato, persiste a
proposta, mostra o conteúdo persistido e pede aprovação. Pedido de apenas
exibição ou sem escrita não autoriza persistir a proposta.

Após aprovação exata, o agente promove o mesmo corpo para uma única coleção
ativa, remove o arquivo de proposta, atualiza `INDEX.md` apenas se o
roteamento mudar e registra a captura ou promoção aprovada em `log.md`. Não
faz outras escritas. Rejeição ou remoção exige direção explícita do
desenvolvedor; não há archive ou contador.
