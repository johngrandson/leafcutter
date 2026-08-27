# Transformations, Enrichments e Interceptors

> **Status: RATIFICADO — NÃO MATERIALIZADO.**

## Transformation

Função pura que converte dado validado em payload de negócio.

Contracts planejados:

```text
1 → 1   {:ok, payload}
1 → N   {:ok, payloads}
1 → 0   :skip
error   {:error, reason}
```

Não faz HTTP, Repo, secret resolution ou logging de side effect.

## Enrichment

Side effect opcional executado antes da Transformation quando dados adicionais são necessários.

```text
validated source
→ prepare enrichment request
→ Connector Operation
→ persist result/status
→ Transformation
```

A definição pertence à PackageVersion; o resultado de execução pertence a Executions.

## Interceptor

Adapta comunicação, não regra de negócio:

- correlation ID;
- custom header/query;
- signing;
- URL adjustment;
- tracing metadata.

Será declarado explicitamente pelo Package. Interceptor global invisível é evitado.

## Limites iniciais

- sem N→1 ou joins stateful;
- sem side effect escondido em `transform`;
- sem body mutation depois da destination validation no desenho inicial;
- sem framework genérico antes dos primeiros contracts reais.
