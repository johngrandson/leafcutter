# Twelve-Factor e Leafcutter

- Estado: PESQUISA NÃO NORMATIVA
- Atualizado para o control plane materializado em agosto de 2026

## Objetivo

Usar os princípios Twelve-Factor como lente de revisão, não como regra que substitui OTP, ADRs ou necessidades do produto.

## Leitura

1. `01-fundamentos-e-vocabulario.md` — fundamentos.
2. `02-fatores-codebase-a-backing-services.md` — codebase, deps, config e backing services.
3. `03-fatores-build-a-concurrency.md` — build/release/run, processes, port binding e concurrency.
4. `04-fatores-disposability-a-admin-processes.md` — disposability, parity, logs e admin processes.
5. `05-roadmap-leafcutter.md` — aderência atual e próximos gaps.
6. `06-checklist-para-agentes.md` — perguntas para review.
7. `STATUS_UPDATE_2026-08-26.md` — snapshot datado que registra como o repositório evoluiu após a pesquisa original.

## Estado atual relevante

Materializado:

- uma codebase/umbrella;
- dependencies explícitas por Mix;
- backing services explícitos;
- processos OTP reconstruíveis;
- graceful recovery model;
- quality gates;
- uma release homogênea planejada.

Ainda aberto:

- runtime config completa;
- release/deploy de produção;
- cluster discovery;
- logs/metrics stack;
- admin processes operacionais;
- secrets provider;
- package build strategy.

## Regra

Quando Twelve-Factor entrar em tensão com durabilidade/fencing/OTP do Leafcutter, registrar o tradeoff. Não aplicar checklist mecanicamente.

Os arquivos de pesquisa preservam o contexto em que foram escritos. Para o estado atual, prevalecem código, testes, ADRs aceitos, `../../checkpoint/CURRENT.md` e `../../architecture/estado-atual-e-visao-futura.md`.