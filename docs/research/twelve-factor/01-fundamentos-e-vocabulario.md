# Twelve-Factor: fundamentos, limites e vocabulário

> Pesquisa realizada em 25 de agosto de 2026. Material de aprendizagem e
> apoio ao planejamento. Não é um ADR, não ratifica decisões arquiteturais e
> não substitui [`CURRENT.md`](../../checkpoint/CURRENT.md).

[Voltar ao índice](README.md)

## O que o Twelve-Factor é, e o que não é

### O problema que a metodologia tenta resolver

O manifesto nasceu da experiência de construir e operar aplicações SaaS. Seus
objetivos declarados incluem setup automatizável, contrato claro com o sistema
operacional, portabilidade, pouca divergência entre desenvolvimento e produção
e escala sem troca substancial das práticas de desenvolvimento
([introdução oficial](https://12factor.net/)).

Isso delimita seu alcance. O Twelve-Factor fala principalmente da interface
entre código e plataforma. A própria FAQ da atualização diz que ele não tenta
reunir tudo o que importa em engenharia de software e não pretende transformar
DRY, YAGNI ou KISS em fatores
([FAQ oficial da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
Portanto, ele não substitui o Context Map, os ADRs, o modelo de durabilidade, a
segurança, o desenho da API ou a estratégia de testes do Leafcutter.

### A doutrina publicada e a revisão em andamento

Há três camadas que não devem ser misturadas:

1. O manifesto publicado contém os doze fatores e continua sendo a referência
   estável disponível em `12factor.net`.
2. A visão da atualização preserva a ideia de um contrato claro entre aplicação
   e plataforma e quer separar fatores, exemplos e recomendações operacionais
   ([visão oficial](https://github.com/twelve-factor/twelve-factor/blob/next/VISION.md)).
3. Os textos do branch `next` são trabalho em andamento. A FAQ reconhece que
   containers, Kubernetes e outras práticas se tornaram comuns, e que detalhes
   sobre observabilidade, segurança e configuração precisam ser modernizados
   ([FAQ oficial da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).

O ponto sensato é conservar os princípios e questionar exemplos datados. Env
vars, `stdout`, processos descartáveis e releases imutáveis continuam sendo
boas ferramentas mentais. Nenhuma delas, isoladamente, resolve secret
management, traces, supply chain, migrações sem downtime ou recuperação de
dados.

### Quatro termos que mudam de significado no Leafcutter

#### App

No manifesto, uma app possui uma codebase e muitos deploys. Se partes têm
codebases e ciclos de deploy independentes, o texto as considera aplicações de
um sistema distribuído ([fator I](https://12factor.net/codebase)).

Para o desenho atual, a unidade correspondente à app é a release homogênea do
Leafcutter, não cada OTP application. `leafcutter_core`,
`leafcutter_connectors`, `leafcutter_runtime` e `leafcutter_api` são divisões
internas propostas de uma mesma unidade de deploy
([umbrella e dependências](../../architecture/umbrella-e-dependencias.md)). Se um
dia API e runtime ganharem releases independentes, cada release deverá ser
avaliada como uma app separada.

#### Process

No manifesto, process é uma instância da aplicação administrada pela plataforma
ou pelo sistema operacional. Um processo Erlang é outra coisa. Uma única BEAM
pode supervisionar milhares de processos Erlang e ainda corresponder a um único
processo da formação descrita pelo Twelve-Factor. O próprio fator de concorrência
permite multiplexação interna por threads, VMs ou modelos assíncronos, mas exige
que a aplicação também consiga ocupar várias instâncias e máquinas
([fator VIII](https://12factor.net/concurrency)).

#### Environment

No fator de configuração, environment é o conjunto de variáveis fornecidas a um
deploy. Em `Organizations`, `Environment` é uma entidade de domínio que separa
configuração e operação de um cliente, como homologação e produção
([contextos e ownership](../../architecture/contextos-e-ownership.md)). Uma
release de produção pode atender muitos `Organizations.Environment`; esses
registros não devem virar milhares de env vars do processo.

#### Release

No Twelve-Factor, release é um build da plataforma combinado com a configuração
de um deploy. No Leafcutter, `PackageVersion`, `EnvironmentDeployment` e
`RunSnapshot` são artefatos e registros de domínio. Os dois eixos precisam de
identidades próprias. Uma release do Leafcutter pode executar muitas Package
Versions, e um Run Snapshot não identifica o binário da plataforma que o
processou.

## Onde o Twelve-Factor não basta para o Leafcutter

### Segurança

Separar config de código reduz vazamento acidental, mas não define criptografia,
controle de acesso, rotação, redaction ou resposta a incidente. A atualização
oficial cita segurança como uma área que precisa de recomendações modernas
([FAQ da atualização](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
O Leafcutter deve continuar tratando `Connections`, SecretVersion, payload
access e permission matrix em seus próprios documentos e decisões.

### Durabilidade e semântica de integração

Os fatores dizem onde estado persistente deve ficar, mas não definem atomicidade
de fan-out, idempotency entre sistemas, sucesso parcial, retry ou fencing. Os
ADRs 0009, 0010 e 0011 são mais importantes para a correção do data plane do que
qualquer checklist genérico.

### Observabilidade completa

Enviar logs à saída padrão não produz metrics, traces, SLOs, alertas ou
diagnóstico de alta cardinalidade. A modernização oficial também reconhece
observabilidade como tema a atualizar. O Leafcutter já separa Execution
Monitoring de Platform Observability; precisa preservar essa separação na
implementação.

### Operação de dados

Backups, restore testado, retenção, migração de schema, object storage e
sequenciamento de deploy não são resolvidos pelos fatores. A topologia de
Postgres e backups continua aberta, enquanto retenção e externalização de
payloads são evoluções planejadas
([storage e retenção](../../architecture/storage-e-retencao.md)).

### Workloads longos e stateful

A FAQ da atualização diz que o trabalho começa pela restrição simplificadora de
apps stateless orientadas a requests antes de ampliar para outros workloads
([FAQ oficial](https://github.com/twelve-factor/twelve-factor/blob/next/UPDATE_FAQ.md)).
O Leafcutter combina API, schedules, jobs duráveis e Runs longos. Ele deve aplicar
o princípio de estado reconstruível, sem fingir que todo trabalho cabe no modelo
de request HTTP curta.

### Arquitetura interna

O Twelve-Factor não decide contexts, boundaries de OTP applications, APIs
públicas ou ownership de schemas. `Organizations`, `Catalog`, `Connections` e
`Integrations` continuam governados pelo Context Map e pelos ADRs locais. Usar
os fatores como desculpa para criar microservices, filas ou wrappers genéricos
seria uma leitura errada do método.
