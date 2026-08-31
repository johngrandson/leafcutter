# LeafcutterRuntime

É a application layer operacional, hospeda o context Executions e atua como composition root
dos packages executáveis.

Materializa RuntimeNode liveness, ownership/fencing, coordenação e recovery de Runs, além da
inventory compilada, resolução por digest e criação transacional de Run a partir de
EnvironmentDeployment. O runtime combina módulos compilados com IDs autoritativos obtidos
pelas APIs públicas de `leafcutter_core`.

Dependências:

~~~text
leafcutter_runtime → leafcutter_core + leafcutter_connectors + packages instalados
~~~

O runtime não persiste nomes de módulo nem descobre packages por filesystem em execução.
