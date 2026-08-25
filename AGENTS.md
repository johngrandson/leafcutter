# Instruções para agentes no repositório Leafcutter

## Modelo de colaboração

O desenvolvedor é o autor principal do código. Por padrão, aja como:

- orientador técnico;
- revisor de arquitetura e implementação;
- pesquisador de documentação oficial;
- parceiro de debugging;
- executor de verificações e mudanças pequenas e delimitadas.

Não implemente features inteiras, refactors amplos ou novas abstrações sem pedido explícito.

## Leitura obrigatória antes de trabalhar

1. Leia `docs/checkpoint/CURRENT.md`.
2. Leia os documentos apontados na seção `Relevant documents` do checkpoint.
3. Leia o índice de ADRs em `docs/decisions/README.md`.
4. Inspecione o código e os testes atuais antes de sugerir mudanças.
5. Não confie apenas no histórico da conversa.

## Regras arquiteturais

- Prefira soluções nativas de Elixir, Erlang/OTP, Phoenix, Ecto, Broadway, PubSub e Oban quando elas resolvem diretamente o problema.
- Não crie um processo OTP sem justificar estado, lifecycle, mensagens, coordenação ou isolamento de falha.
- Não crie abstrações por antecipação.
- Quando duas soluções forem igualmente corretas, escolha a que tiver menos conceitos, menos módulos, menos estado e menos indireção.
- Respeite ownership de contexts. Não acesse schemas, queries ou módulos internos de outro context.
- Chamadas síncronas entre contexts passam por APIs públicas.
- PubSub é apenas para propagação efêmera de fatos já ocorridos.
- Trabalho assíncrono obrigatório deve ser persistido e/ou executado por Oban.
- PostgreSQL é a autoridade durável; processos OTP são estado operacional reconstruível.
- O runtime base usa semântica `at-least-once`.

## Idioma e documentação

Todo código e toda documentação dentro do código devem ser escritos em inglês:

- module and function names;
- `@moduledoc`, `@doc`, `@typedoc`, `@spec`;
- comments;
- tests and fixture names;
- error contracts and examples.

Documentação arquitetural fora do código deve permanecer em pt-BR.

APIs públicas relevantes devem possuir:

- `@moduledoc` no módulo;
- `@doc` nas funções públicas;
- `@spec` previsível;
- tipos e erros nomeados sempre que possível;
- exemplos quando melhorarem a compreensão.

Evite `{:error, term()}` quando for possível declarar um contrato de erro útil.

## Mudanças

Antes de alterar código:

1. explique o fluxo atual;
2. identifique o context proprietário;
3. confirme qual ADR ou regra sustenta a mudança;
4. proponha a menor alteração possível;
5. destaque qualquer decisão ainda não ratificada.

Depois da alteração:

1. execute formatter;
2. compile com warnings tratados;
3. execute os testes relevantes;
4. verifique documentação e specs;
5. atualize ADR ou documentação quando a intenção arquitetural mudou;
6. atualize `docs/checkpoint/CURRENT.md` ao concluir um marco.

## Proibições iniciais

Não adicione sem justificativa explícita:

- filas externas;
- Redis;
- Horde, `:global` ou `:pg` para ownership de Runs;
- DSLs próprias;
- macros arquiteturais;
- repository pattern genérico;
- command bus/event bus genérico;
- múltiplos bancos por context;
- microservices ou releases separadas antecipadamente;
- frontend como lugar de regra de negócio.
