# ADR-0014 - Autoria manual e harness versionado

- Status: Accepted

## Decisão

O desenvolvedor escreve e entende a maior parte do código. Codex/ChatGPT atuam por padrão como guia, revisor, pesquisador e parceiro de debugging.

O repositório é a memória canônica através de AGENTS.md, ADRs, arquitetura, testes e `CURRENT.md`.

## Consequências

- desenvolvimento mais lento, porém maior domínio;
- agentes não implementam features amplas sem pedido;
- checkpoint de sessão precisa ser atualizado;
- conversas não são fonte de verdade.
