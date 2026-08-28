# Implementação

Esta pasta traduz a arquitetura ratificada em sequência de slices, gates e critérios de conclusão.

## Estado

A foundation inicial e RunSnapshot v1 já foram concluídos. As authorities upstream mínimas e o resolver de `EnvironmentDeployment` foram ratificados no ADR-0018. Connector, ConnectorVersion, Operation, Contract, ContractVersion, Package, PackageVersion e PackageVersionEndpoint materializam o Catalog mínimo. Connections e SecretVersion bindings iniciam a próxima sequência.

## Documentos

- `sequence.md`: ordem materializada e próximos slices.
- `first-milestone.md`: o primeiro milestone, agora concluído, e seu resultado.
- `definition-of-done.md`: critérios mínimos para considerar uma mudança concluída.
- `quality-gates.md`: comandos locais e checks obrigatórios.

## Regra

Uma implementação não está concluída quando apenas compila. Ela precisa manter alinhados:

```text
code
tests
types/docs
ADRs
architecture status
CURRENT.md
```

Não materializar uma parte futura sem ratificação. Não apagar o futuro ratificado ao documentar um slice menor.
