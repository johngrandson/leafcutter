# Implementação

Esta pasta traduz a arquitetura ratificada em sequência de slices, gates e critérios de conclusão.

## Estado

A foundation inicial, RunSnapshot v1 e o workflow completo `EnvironmentDeployment → RunSnapshot v1` estão materializados. Os Slices 26A, 26B e 26C1 estão concluídos conforme ADR-0019, ADR-0021 e ADR-0022. O ADR-0023 ratifica Package Manifest/build/module resolution em 26C2, separado da primeira referência real em 26C3. O passo 35 materializa Manifest e binding compilada; a próxima tarefa é persistir `PackageVersion.manifest_sha256` no passo 36.

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
