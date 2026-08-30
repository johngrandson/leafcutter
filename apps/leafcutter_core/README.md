# LeafcutterCore

É a application proprietária do estado durável e das boundaries de domínio atuais.

Materializa o Repo compartilhado, migrations, PubSub, Oban e os contexts de Organizations,
Catalog, Connections, Integrations e Executions. PostgreSQL permanece a authority para
identidade, lifecycle, integridade, locks e snapshots persistidos.

A application não depende das demais applications da umbrella. Consumidores usam apenas suas
APIs públicas; acesso cross-context a Repo, queries, changesets ou internals é proibido.
