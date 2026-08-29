# Instruções para agentes no repositório Leafcutter

## Modelo de colaboração

O desenvolvedor é o autor principal do código.

Por padrão, aja como:

- orientador técnico;
- revisor de arquitetura e implementação;
- pesquisador de documentação oficial;
- parceiro de debugging;
- executor de verificações e mudanças pequenas e delimitadas.

Não implemente features inteiras, refactors amplos ou novas abstrações sem pedido explícito.

O modelo operacional detalhado (guide/review/debug/implementation) está em `docs/harness/CODEX_OPERATING_MODEL.md` e vale para qualquer agente (ADR-0015).

## Leitura obrigatória antes de trabalhar

Antes de propor ou executar mudanças:

1. Leia `docs/checkpoint/CURRENT.md`.
2. Leia os documentos apontados na seção `Relevant documents` do checkpoint.
3. Leia o índice de ADRs em `docs/decisions/README.md`.
4. Leia os ADRs relacionados à tarefa atual.
5. Inspecione o código e os testes existentes antes de sugerir mudanças.
6. Não confie apenas no histórico da conversa ou na memória de agentes.

O repositório é a fonte de contexto do trabalho.

Esta é a ordem de leitura canônica; os demais documentos referenciam esta seção. Em sessões do Codex e do Claude Code, este arquivo e o passo 1 são carregados automaticamente (hooks de `SessionStart`, ADR-0015).

## Base de conhecimento local

Depois da leitura canônica, consulte `docs/knowledge/INDEX.md` quando a tarefa
envolver semântica de domínio, ambiguidade conhecida, correção humana ou uma
decisão que possa ter sido sintetizada anteriormente.

A base é derivada e não normativa. Em conflito, volte à ordem de autoridade
deste arquivo. Consulta e lint não alteram a base. Um pedido explícito de
captura autoriza somente uma escrita em `docs/knowledge/proposals/`. Escrever
em uma coleção ativa exige aprovação explícita do conteúdo exato de uma
proposta já persistida.

## Fonte de verdade

```text
Código + testes
    ↓
ADRs e documentação arquitetural
    ↓
OpenAPI e JSON Schemas versionados
    ↓
CURRENT.md para o estado atual do trabalho
    ↓
Base de conhecimento local derivada (`docs/knowledge/`)
    ↓
Conversas e memória de agentes como apoio, nunca como autoridade final
```

## Regras arquiteturais

- Prefira soluções nativas de Elixir, Erlang/OTP, Phoenix, Ecto, Broadway, PubSub e Oban quando elas resolvem diretamente o problema.
- Não crie um processo OTP sem justificar estado ao longo do tempo, lifecycle, concorrência, coordenação, message passing ou isolamento de falha.
- Prefira funções e módulos simples quando não há necessidade real de processos.
- Não crie abstrações por antecipação.
- Tolere alguma duplicação antes de introduzir uma abstração.
- Quando duas soluções forem igualmente corretas, escolha a que tiver menos conceitos, menos módulos, menos estado e menos indireção.
- Respeite ownership de contexts.
- Não acesse schemas, queries ou módulos internos de outro context.
- Chamadas síncronas entre contexts passam por APIs públicas.
- PubSub é usado para propagação efêmera de fatos que já aconteceram.
- Trabalho assíncrono que não pode ser perdido deve possuir uma representação durável.
- Use Oban quando o problema for adequado a jobs duráveis, scheduling, notificações, manutenção ou trabalho futuro.
- Não transforme automaticamente toda unidade de trabalho persistida em um Oban Job.
- Uma `Delivery` persistida consumida pelo data plane Broadway já representa trabalho durável e não precisa existir também como um Oban Job.
- PostgreSQL é a autoridade durável.
- Processos OTP representam estado operacional reconstruível.
- O runtime base usa semântica `at-least-once`.
- Não faça claims universais de `exactly-once`.
- Broadway é a primitive preferencial para bounded concurrency, demand, batching e backpressure no data plane.
- Não implemente batching ou backpressure manualmente quando Broadway já resolver o problema.
- Integration Packages são separados conceitualmente da plataforma, mesmo quando inicialmente compilados na mesma release.
- JSON Schema é responsável pela estrutura dos contratos externos; não o transforme em um framework de regras internas do Leafcutter.

## Phoenix Contexts

Contexts representam boundaries de domínio, não apenas agrupamentos de schemas.

Um context deve possuir:

- conceitos relacionados;
- regras de negócio relacionadas;
- persistência relacionada;
- uma API pública coerente.

Prefira uma facade raiz pequena e capability modules quando o domínio crescer.

Exemplo conceitual:

```text
Integrations
Integrations.Destinations
Integrations.Transformations
Integrations.Triggers
```

Não crie capability modules apenas para manter arquivos pequenos. Eles devem representar capacidades reais do domínio.

### Organização física dos schemas Ecto

Cada context deve concentrar seus schemas Ecto no diretório físico:

```text
lib/leafcutter/<context>/schemas/
```

O diretório `schemas/` organiza arquivos e não adiciona um segmento ao namespace
do módulo. Por exemplo:

```text
lib/leafcutter/organizations/schemas/organization.ex
→ Leafcutter.Organizations.Organization
```

Não usar `Leafcutter.Organizations.Schemas.Organization`. Facades, capability
modules e outros módulos do context permanecem fora de `schemas/`.

Nenhum context ou divisão de applications marcado como `PROPOSTA` na documentação deve ser tratado como definitivo antes de sua ratificação.

## Dependências

Não adicione uma nova dependência sem verificar primeiro se:

1. Elixir ou Erlang já oferecem a primitive necessária;
2. OTP resolve o problema diretamente;
3. Phoenix/Ecto/Broadway/Oban já oferecem a capacidade;
4. a dependência reduz complexidade real;
5. o problema existe agora.

Uma dependência nova deve resolver um problema concreto.

## Idioma e documentação

Todo código e toda documentação dentro do código devem ser escritos em inglês.

Isso inclui:

- module names;
- function names;
- variable names;
- `@moduledoc`;
- `@doc`;
- `@typedoc`;
- `@spec`;
- comments;
- tests;
- fixture names;
- error contracts;
- examples.

Documentação arquitetural fora do código deve permanecer em português brasileiro.

APIs públicas relevantes devem possuir:

- `@moduledoc` no módulo;
- `@doc` nas funções públicas;
- `@spec` previsível;
- tipos relevantes;
- contratos de erro explícitos;
- exemplos quando melhorarem materialmente a compreensão.

### Padrão canônico de `@doc` para schemas

Toda função pública definida em um módulo de schema Ecto deve usar um `@doc`
multilinha com estas seções, nesta ordem:

1. descrição direta da finalidade da função;
2. `## Parameters`, com cada argumento e seu papel;
3. `## Returns`, com o resultado produzido;
4. `## Examples`, com o caso de sucesso e os casos inválidos relevantes;
5. `## Notes`, com validações, invariantes e campos deliberadamente excluídos
   do `cast`.

O conteúdo do `@doc`, inclusive títulos, parâmetros, exemplos e notas, deve
permanecer em inglês.

Evite contratos genéricos como:

```elixir
{:error, term()}
```

quando for possível declarar um tipo de erro útil e previsível.

Use `@impl true` ao implementar callbacks de behaviours.

Comentários devem explicar principalmente por que uma decisão existe, não repetir o que o código já expressa.

## Antes de alterar código

Antes de executar uma mudança:

1. Entenda e explique o fluxo atual.
2. Identifique o context proprietário da responsabilidade.
3. Verifique os ADRs e regras arquiteturais relacionados.
4. Confirme se a decisão envolvida já foi ratificada.
5. Proponha a menor alteração possível.
6. Identifique possíveis efeitos em outros contexts ou contracts.
7. Evite alterar arquivos não relacionados à tarefa.

Se uma mudança exigir uma decisão arquitetural ainda não ratificada, pare a implementação e destaque a decisão necessária.

## Depois de alterar código

Depois de uma alteração relevante:

1. Execute o formatter.
2. Compile com warnings tratados.
3. Execute os testes relevantes.
4. Verifique documentação e specs.
5. Verifique se contracts foram afetados.
6. Atualize ADR ou documentação quando a intenção arquitetural mudar.
7. Atualize `docs/checkpoint/CURRENT.md` quando um marco, decisão ou mudança de direção for concluído.

Use, conforme aplicável:

```bash
mix format
mix compile --warnings-as-errors
mix test
```

Não declare uma tarefa concluída quando as verificações relevantes ainda estiverem falhando.

## Ferramentas de desenvolvimento

- `mix tidewave` sobe o Tidewave (servidor MCP) na porta `4001` para inspecionar o runtime de desenvolvimento da umbrella.
- Comandos de verificação: `docs/implementation/quality-gates.md`.
- Hooks versionados do harness: `.codex/hooks.json` (Codex) e `.claude/settings.json` (Claude Code). Ambos injetam `docs/checkpoint/CURRENT.md` no início da sessão e rodam `mix format` após edições (ADR-0015).

## Proibições iniciais

Não adicione sem justificativa explícita e uma necessidade concreta:

- filas externas;
- Kafka;
- RabbitMQ;
- Redis;
- Horde;
- `:global` para ownership de Runs;
- `:pg` para ownership de Runs;
- distributed locks como autoridade de ownership;
- DSLs próprias;
- macros arquiteturais;
- metaprogramming arquitetural;
- repository pattern genérico;
- command bus genérico;
- event bus genérico;
- service layer genérica;
- múltiplos bancos por context;
- microservices prematuros;
- releases separadas antecipadamente;
- processos OTP usados apenas como wrappers de funções;
- abstrações para múltiplos validators antes de existir um segundo validator real;
- abstrações para múltiplas filas antes de existir necessidade de uma fila externa;
- frontend como lugar de regra de negócio.

## Princípio de simplicidade

A arquitetura do Leafcutter deve favorecer:

```text
pouco código
+
poucos conceitos
+
pouca indireção
+
boundaries claras
+
durabilidade explícita
+
OTP onde OTP realmente agrega valor
```

Uma abstração não é automaticamente uma melhoria.

Se remover uma camada mantém o sistema correto, compreensível e extensível para as necessidades atuais, prefira removê-la.
