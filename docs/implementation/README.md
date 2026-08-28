# Implementação

Esta pasta traduz a arquitetura ratificada em sequência de slices, gates e critérios de conclusão.

## Estado

A foundation inicial e RunSnapshot v1 já foram concluídos. A sequência atual começa na ratificação das authorities upstream mínimas e do resolver de `EnvironmentDeployment` para uma definition v1.

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
