# Princípios e restrições arquiteturais

## Objetivo

O Leafcutter deve ser compreensível e implementável manualmente por um desenvolvedor experiente, sem depender de geração massiva de código. A arquitetura deve suportar crescimento real sem exigir que a primeira versão carregue toda a infraestrutura de uma plataforma madura.

## Ordem de preferência

Ao resolver um problema:

```text
1. Standard library de Elixir/Erlang
2. Primitive OTP
3. Phoenix/Ecto/PubSub/Broadway/Oban
4. Função ou módulo simples
5. Abstração própria apenas quando as opções anteriores não resolvem adequadamente
```

## Simplicidade

Simplicidade significa:

- poucos conceitos;
- fluxo explícito;
- ownership claro;
- funções puras no centro;
- efeitos nas bordas;
- pouca indireção;
- documentação próxima do código.

Simplicidade não significa arquivos gigantes, responsabilidades misturadas ou ausência de boundaries.

## SRP e Contexts

Cada context responde por uma capacidade de negócio. Cada context possui:

- API pública explícita;
- schemas e queries próprios;
- capability modules quando a facade raiz começaria a crescer;
- módulos internos não consumidos por outros contexts.

Nenhum context acessa diretamente schemas ou queries internos de outro context.

## Regra para APIs públicas

A facade raiz responde por operações sobre o conceito principal:

```elixir
Integrations.create(...)
Integrations.activate(...)
Integrations.disable(...)
```

Capacidades específicas ficam segmentadas:

```elixir
Integrations.Destinations.add(...)
Integrations.Triggers.schedule(...)
```

Não reexportar todas as funções pelo módulo raiz.

## DRY e YAGNI

- Não abstrair por antecipação.
- Tolerar duplicação local pequena até a regra comum estar clara.
- Extrair quando a mesma regra de negócio possa divergir ou quando a abstração reduzir complexidade real.
- Não adicionar infraestrutura para uma escala ainda não medida.

## OTP

Um processo só entra quando existe pelo menos uma justificativa concreta:

- estado ao longo do tempo;
- lifecycle próprio;
- message passing;
- coordenação concorrente;
- isolamento de falha;
- supervisão e reconstrução.

Caso contrário, usar função ou módulo normal.

## Estado

```text
PostgreSQL
→ estado durável, histórico, ownership e checkpoints

OTP/Broadway
→ estado operacional, concorrência, demand e lifecycle

PubSub
→ propagação efêmera de fatos

Oban
→ trabalho futuro ou obrigatório que precisa sobreviver a crashes
```

## Behaviours

Behaviours são permitidos somente em fronteiras realmente polimórficas:

- Connector/Operation;
- Transport;
- Transformation;
- Enrichment preparation;
- Interceptor;
- provedores de secret quando houver mais de uma implementação real.

Não criar behaviour para regras que podem ser módulos puros.

## Linguagem e documentação

Dentro do código, tudo em inglês:

```text
modules
functions
types
specs
moduledocs
docs
comments
tests
errors
```

Fora do código, arquitetura e roadmap em pt-BR.

A documentação in-code é uma interface de desenvolvimento. APIs públicas devem ter tipos e erros previsíveis.

## Critério de desempate

Quando duas soluções forem igualmente corretas, escolher a que tiver:

```text
menos conceitos
menos módulos
menos estado
menos indireção
menor custo operacional
maior facilidade de compreensão manual
```
