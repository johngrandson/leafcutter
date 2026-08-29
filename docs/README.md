# Documentação do Leafcutter

A documentação do Leafcutter separa explicitamente **estado materializado**, **arquitetura ratificada para o futuro**, **decisões em aberto** e **material de pesquisa**.

## Ordem de autoridade

~~~text
Código + testes
    ↓
ADRs aceitos
    ↓
Documentação arquitetural ratificada
    ↓
Specifications e OpenAPI versionados
    ↓
CURRENT.md para o ponto de continuidade
    ↓
Research e conversas como apoio
~~~

Quando um documento divergir do código, o código e os testes prevalecem. Quando a divergência representar mudança intencional de arquitetura, o ADR e a documentação devem ser atualizados antes de tratar a mudança como consolidada.

## Vocabulário de estado

| Estado | Significado |
|---|---|
| **MATERIALIZADO** | Existe no código e possui cobertura compatível com o estágio atual. |
| **PARCIALMENTE MATERIALIZADO** | Parte do desenho está no código; o documento preserva também a evolução ratificada. |
| **RATIFICADO — NÃO MATERIALIZADO** | A direção foi aprovada, mas ainda não existe implementação completa. |
| **ABERTO** | A decisão ainda precisa ser fechada antes de implementação. |
| **PESQUISA** | Referência não normativa; não altera a arquitetura por si só. |
| **TEMPLATE** | Estrutura operacional reutilizável. |

A convenção completa está em `architecture/estado-atual-e-visao-futura.md` e no ADR-0016.

## Começo recomendado

1. `checkpoint/CURRENT.md` — estado atual e próxima decisão.
2. `architecture/estado-atual-e-visao-futura.md` — mapa entre presente e futuro.
3. `architecture/visao-geral.md` — visão resumida.
4. `architecture/contextos-e-ownership.md` — boundaries de domínio.
5. `architecture/umbrella-e-dependencias.md` — boundaries das OTP applications.
6. `architecture/runtime-otp-broadway.md` — runtime materializado e data plane planejado.
7. `decisions/README.md` — decisões e estado de implementação.
8. `implementation/README.md` — sequência prática e gates.

## Áreas

### Arquitetura

`architecture/README.md` indexa todos os documentos e informa se cada um descreve estado atual, futuro ratificado ou ambos.

### Decisões

`decisions/README.md` contém o índice de ADRs, seu status decisório e seu estado de implementação.

### Checkpoint

- `checkpoint/CURRENT.md`: estado vivo do projeto.
- `checkpoint/SESSION_BOOTSTRAP.md`: leitura mínima para iniciar uma sessão.

### Implementação

`implementation/README.md` conecta o roadmap arquitetural aos slices de código e aos quality gates.

### Specifications

`specifications/README.md` diferencia contracts já materializados de specifications ratificadas ainda não materializadas, incluindo o Slice 26A de ContractVersion executável.

### Produto

`product/README.md` separa capacidades já disponíveis como foundation das capacidades completas do produto planejado.

### Harness

`harness/README.md` descreve colaboração com agentes, handoff, revisão e protocolo de mudanças.

### Pesquisa

`research/README.md` contém material não normativo. Pesquisa pode motivar uma proposta, mas não substitui ADR nem ratificação.

### Base de conhecimento

A base de conhecimento é **DERIVADA**: ela facilita consultas locais, mas não
substitui código, testes, ADRs, documentação ratificada, specifications,
OpenAPI ou `CURRENT.md`. Consulte [o schema](knowledge/README.md) e [o índice
de roteamento](knowledge/INDEX.md).

### Templates

`templates/README.md` contém modelos para ADR, checkpoint e milestone já alinhados à separação entre presente e futuro.
