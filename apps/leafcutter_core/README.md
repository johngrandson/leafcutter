# LeafcutterCore

É a application proprietária da infraestrutura de persistência compartilhada e das
boundaries de domínio duráveis que hospeda.

Materializa o Repo compartilhado, migrations, PubSub, Oban e os contexts de Organizations,
Catalog, Connections e Integrations. PostgreSQL permanece a authority para identidade,
lifecycle, integridade, locks e snapshots persistidos.

As migrations são centralizadas nesta application, inclusive para tabelas de contexts
pertencentes a outras applications. Essa centralização não transfere o ownership do domínio.

A application não depende das demais applications da umbrella. Consumidores usam apenas suas
APIs públicas; acesso cross-context a Repo, queries, changesets ou internals é proibido.
