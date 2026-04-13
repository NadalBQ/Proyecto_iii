# M8 - Red viaria canonica y contrato de matching

## Por que esta red es la unidad canonica correcta
- ROAD-SAFETY necesita una unidad espacial operativa para routing. Esa unidad no puede ser el accidente raw ni un tramo de trafico auxiliar: tiene que ser la arista del grafo.
- Por eso M8 construye una red canonica de `nodes/edges` desde OpenStreetMap, usando un extracto estable de Geofabrik para Madrid, y la guarda en `EPSG:25830` para distancias y matching en metros.
- El CSV de tramos de trafico sigue fuera de la definicion del edge final; puede servir despues como capa contextual, no como sustituto del backbone de routing.

## Que queda listo tras M8
- Red canonica preparada desde `https://download.geofabrik.de/europe/spain/madrid-latest-free.shp.zip` y normalizada a `EPSG:25830`.
- `nodes` y `edges` con IDs estables, geometrias validas y relaciones `from_node_id` / `to_node_id` trazables. Estado de backbone minimo: `TRUE`.
- Contrato tecnico de matching accidente -> edge documentado, incluyendo distancia punto-edge, radio de busqueda, numero de candidatos y banderas de calidad.
- El schema final esperado para M9 queda fijado como `m9_schema_v1_edge_id_projected_point_geometry_binary_match_status`: `edge_id` como arista seleccionada, `projected_point_geometry` como WKT en CSV y `match_status` binario con la ambiguedad reflejada en `quality_flag`.
- Separacion metodologica preservada: baseline/contextual, historico_espacial y routing final siguen desacoplados.

## Que faltara en M9
- Ejecutar el map-matching real accidente -> edge contra esta red canonica.
- Definir umbrales operativos de distancia y reglas de calidad y ambiguedad.
- Guardar el match con trazabilidad completa y preparar la agregacion historica por edge.
- Seguir sin convertir todavia el resultado en score final de routing hasta que la capa historica y la exposicion esten cerradas.

