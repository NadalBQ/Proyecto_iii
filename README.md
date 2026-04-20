# ROAD-SAFETY

- `main.py` es el sitio donde se escribe el flujo manual de la aplicacion.
- `src/model.py` es el wrapper publico del modelo.
- `src/build_final_parquet.R` es el unico punto de entrada activo para materializar el parquet final desde datos raw.
- `src/graph.py`, `src/routing.py`, `src/ui.py` y `src/weights.py` quedan reservados para integrar el resto del proyecto.

## Superficie publica

`src/model.py` expone:

- `build_final_parquet(...)`
- `train_model(X, y)`
- `save_model(model, relative_path)`
- `load_model(relative_path)`
- `predict(model, X)`
- `test_model(model, X, y)`

## Dataset final de modelado

El parquet final sigue siendo:

- `training_table_with_exogenous_context_features.parquet`

El contrato activo que se mantiene es:

- target: `accident_count`
- unidad observacional: `edge_id + analysis_year + temporal_bin_4h + is_weekend`

## Materializacion del parquet

La materializacion del parquet ya no depende de una pipeline R visible en varios archivos.
Toda la logica activa de `raw -> parquet` queda unificada en:

- `src/build_final_parquet.R`

Desde Python, la llamada publica es:

- `build_final_parquet(accidents_csv_path, output_parquet_path, network_zip_path=None, force=False)`

Inputs locales esperados:

- CSV de accidentes
- opcionalmente un zip de red OSM para enriquecer el matching y las features exogenas

Si `Rscript` no esta disponible o falta algun input, `src/model.py` devuelve un error claro.

## Rol de main.py

`main.py` no contiene logica interna de R ni pasos intermedios de preparacion.
Solo queda preparado para que luego se escriba el flujo manual del proyecto, conectando:

1. materializacion del parquet
2. entrenamiento o carga del modelo
3. prediccion
4. integracion con grafos, pesos y rutas
