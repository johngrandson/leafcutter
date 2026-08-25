# Contracts com JSON Schema

## Decisão

JSON Schema Draft 2020-12 é a fonte única de verdade estrutural para payloads de entrada e saída.

JSV é o primeiro validator do Leafcutter.

```text
external JSON
    ↓ decode
Elixir JSON-compatible values
    ↓ JSV source validation
trusted source payload
    ↓ Transformation
candidate destination payload
    ↓ JSV destination validation
valid output
```

## Representação interna

O runtime trabalha com:

- maps com chaves string;
- lists;
- strings;
- numbers;
- booleans;
- `nil`.

Não gerar um módulo/struct Elixir para cada Contract dinâmico.

## Imutabilidade

Contract Versions são imutáveis. Runs registram exatamente quais versões foram usadas.

## `$ref`

Referências são suportadas, mas dependências remotas devem ser resolvidas e congeladas no momento de registro/publicação do Contract. Um Run nunca deve depender da internet para compreender seu schema.

## Compilação

Schemas são compilados fora do hot path e reutilizados.

```text
Contract Version
    ↓ compile once
compiled JSV validator
    ↓ cache
many validations
```

ETS pode ser usado para cache de validators compilados quando a necessidade aparecer. Não criar `ContractCacheServer` antes de medir.

## `format`

O perfil do Leafcutter deve validar formats conhecidos de forma assertiva quando configurado, em vez de tratá-los somente como annotations.

## Contracts e identidade

JSON Schema continua estrutural. Source Identity é propriedade da Operation conhecida ou configuração simples do Package no caso genérico. Não sobrecarregar schemas com um framework de metadata próprio.

## Manifest

O próprio `manifest.json` também possui um JSON Schema versionado e validado por JSV.

## Erros

Erros de Contract devem manter:

- contract/version;
- path do campo;
- expectativa;
- valor recebido de forma segura/redigida;
- Record/Delivery relacionado;
- classificação `:validation`.
