# LeafcutterApi

É a boundary Phoenix do Leafcutter e a raiz da release homogênea `:leafcutter`.

Materializa Endpoint, Router, Telemetry e o scaffolding HTTP atual. Regras de domínio
permanecem nos contexts de `leafcutter_core`, enquanto coordenação operacional e
resolução executável pertencem a `leafcutter_runtime`. OpenAPI completo,
autenticação e o error envelope público continuam futuros.

Dependências:

~~~text
leafcutter_api → leafcutter_core + leafcutter_runtime
~~~
