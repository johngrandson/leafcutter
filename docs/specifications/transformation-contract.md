# Transformation contract

- Estado: RATIFICADO — NÃO MATERIALIZADO

Transformation é função pura sobre payload já validado e config não sensível resolvida.

```text
{:ok, payload}       1 → 1
{:ok, [payloads]}    1 → N
:skip                1 → 0
{:error, reason}     controlled failure
```

Não faz HTTP, Repo, secret resolution ou side effect. Enrichment externo é etapa separada.

N→1, joins e aggregation stateful estão fora do contract inicial.

Tipos concretos, error shape e metadata adicional serão fechados com a primeira PackageVersion executável.
