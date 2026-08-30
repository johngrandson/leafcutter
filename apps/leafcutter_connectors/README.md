# LeafcutterConnectors

É responsável pelos contracts executáveis de Operations, pela binding compilada de Packages
e pelas fronteiras de Transport com limites explícitos.

A application materializa behaviours Read/Write, Manifest v1, o contract de Package e o
Transport HTTP de uma tentativa. Sua única árvore de processo supervisiona o cliente Finch
HTTP/1 compartilhado pelos packages instalados.

Não depende de Catalog, Ecto, Repo, `leafcutter_core` ou internals de
`leafcutter_runtime`. Detalhes vendor-specific pertencem às Operations de produto.
