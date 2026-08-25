# ADR-0001 - Umbrella com poucas OTP applications

- Status: Accepted

## Contexto

O Leafcutter possui domínio, runtime concorrente, connectors e API, mas será desenvolvido inicialmente por uma pessoa. Microservices ou muitas apps aumentariam custo e esconderiam o fluxo.

## Decisão

Usar uma umbrella criada com `mix new leafcutter --umbrella`, contendo poucas OTP applications justificadas por boundaries de dependência e lifecycle. Inicialmente tudo sobe em uma única release homogênea.

## Consequências

- boundaries explícitos sem custo de deployments separados;
- possibilidade de separar releases depois;
- necessidade de impedir dependências circulares;
- contexts não precisam virar apps individualmente.
