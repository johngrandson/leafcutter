# Fatores I a IV: código, dependências, configuração e recursos

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## I. Codebase

O fator pede uma codebase versionada e muitos deploys. Desenvolvimento local,
staging e produção executam versões diferentes da mesma história de código
([fator I](https://12factor.net/codebase)).

O repositório atual evidencia uma única raiz Git, uma umbrella e um `mix.exs` no
topo. O ADR aceito escolheu poucas OTP applications e uma release homogênea
inicial ([ADR-0001](../../decisions/ADR-0001-umbrella-com-poucas-apps.md)). O código
de Integration Packages ficará em `packages/`, separado de `apps/`, mas
participará inicialmente do mesmo build e da mesma release
([ADR-0007](../../decisions/ADR-0007-integration-packages.md)). Isso é compatível
com uma codebase monorepo.

Ainda não há deploy. Também falta ratificar como `packages/` entra no build. O
fator não exige transformar cada context em repositório, app OTP ou
microservice. Fazer isso agora contrariaria a decisão de poucas applications e
criaria ciclos de release sem necessidade.

Critérios futuros de verificação:

- uma release deve apontar para um commit e um artifact ID reproduzíveis;
- development, homologation e production devem executar artefatos derivados da
  mesma codebase;
- nenhuma correção pode ser feita editando código dentro de uma instância em
  execução;
- se uma parte ganhar deploy independente, registrar explicitamente a nova
  unidade de app e reavaliar os fatores para ela.

## II. Dependencies

O fator exige declaração completa e isolamento de dependências. A aplicação não
deve depender de bibliotecas ou executáveis que "por acaso" existem na máquina
([fator II](https://12factor.net/dependencies)).

Há evidência parcial: `mix.exs` declara as dependências da raiz e `mix.lock`
congela resoluções. Credo e Dialyxir ficam fora do runtime. Tidewave e Bandit são
somente de desenvolvimento. O gate `mix quality` já verifica a umbrella
([quality gates](../../implementation/quality-gates.md)).

O que falta:

- versão suportada de Erlang/OTP e Elixir versionada no repositório;
- dependências próprias das child applications, que ainda não existem;
- estratégia de dependências e compilação de Integration Packages;
- inventário de bibliotecas nativas, NIFs e pacotes do sistema operacional;
- build de produção que prove não depender do checkout ou do ambiente do
  desenvolvedor.

Uma release Mix pode empacotar código, ERTS e bibliotecas, mas o host de build e
o target ainda precisam ter arquitetura, ABI e bibliotecas de sistema
compatíveis. A documentação oficial também recomenda incluir ERTS e descreve
como NIFs e OpenSSL podem introduzir dependências do sistema
([`mix release`](https://hexdocs.pm/mix/Mix.Tasks.Release.html)). Portanto,
`mix.lock` é necessário, mas não basta para um build reproduzível.

## III. Config

Na doutrina original, config é tudo que varia entre deploys: handles de backing
services, credenciais e valores como hostname. Esse conteúdo deve ficar fora do
código e ser fornecido por controles ortogonais no environment
([fator III](https://12factor.net/config)).

O Leafcutter precisa classificar configuração antes de escolher o mecanismo:

| Classe | Exemplos no Leafcutter | Local conceitual |
|---|---|---|
| Config de deploy | URL do Postgres, host/porta da API, node name, cookie de distribuição, exporter de telemetry | Runtime config da release ou config provider |
| Config de domínio | PackageVersion, destinations, batching permitido, schedules, overrides | Contexts e PostgreSQL, com ownership e histórico |
| Credencial de tenant | OAuth token, API key, SecretVersion | `Connections`, com provider/criptografia ainda pendentes |
| Decisão de build | módulos compilados, dependências, topology estática do pacote | Código e artefato versionado |

O fator se aplica diretamente à primeira linha. Ele não manda armazenar cada
Connection ou Integration em env vars. Esses dados variam por tenant e fazem
parte do domínio durável. O desenho ratificado de `Connections` separa dados
sensíveis de `Connection` e proíbe secrets em manifests, logs e respostas
([contextos e ownership](../../architecture/contextos-e-ownership.md)).

Hoje só existe `config/config.exs`; não há `runtime.exs`, contrato de variáveis,
validação de boot ou secret provider. Essa é uma lacuna, mas a decisão física de
secrets e o provider de infraestrutura continuam explicitamente abertos
([decisões em aberto](../../architecture/decisoes-em-aberto.md)). Releases Mix
executam `config/runtime.exs` no boot e também aceitam config providers para
fontes como vaults ou arquivos
([`mix release`, seção de runtime configuration](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-runtime-configuration)).

Critérios futuros:

- documentar nome, tipo, obrigatoriedade, valor seguro e momento de leitura de
  cada config de deploy;
- falhar cedo e sem imprimir secrets quando uma config obrigatória estiver
  ausente ou inválida;
- não ler config mutável de build em runtime;
- manter config de tenant nas APIs e tabelas dos contexts proprietários;
- decidir o mecanismo de secrets depois que o modelo de `Connections` e o
  ambiente de deploy forem conhecidos.

## IV. Backing services

O fator trata bancos, filas, caches, serviços de email e APIs remotas como
recursos anexados. Código e topologia não devem mudar quando um handle compatível
aponta para outra instância do mesmo tipo de serviço
([fator IV](https://12factor.net/backing-services)).

O Leafcutter já tem uma direção clara:

- PostgreSQL é a autoridade durável
  ([ADR-0004](../../decisions/ADR-0004-estado-operacional-e-duravel.md));
- o backlog inicial também vive no Postgres, sem fila externa antecipada
  ([ADR-0010](../../decisions/ADR-0010-fanout-duravel-sem-fila-externa.md));
- `Connections` representa e resolve acesso de uma Organization e Environment a
  sistemas externos, enquanto Connectors escondem protocolo e semântica da
  operação
  ([contextos e ownership](../../architecture/contextos-e-ownership.md),
  [ADR-0008](../../decisions/ADR-0008-connector-operation-transport.md)).

Isso é direção ratificada, não implementação. Provider, backups, topologia do
Postgres, object storage e fila externa continuam abertos ou futuros. Trocar uma
instância Postgres por outra compatível deve exigir mudança do handle, não do
código. Trocar Salesforce por um ERP com outro contrato não é uma simples troca
de backing service. Pode exigir outro Connector ou Package porque a semântica de
domínio mudou.

O fator também não justifica um repository pattern genérico. Ecto e APIs
públicas dos contexts já podem manter o recurso configurável sem esconder o
domínio atrás de uma camada extra.
