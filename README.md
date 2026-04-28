# ROAD-SAFETY

- `main.py` es el sitio donde se escribe el flujo manual de la aplicacion.
- `src/model.py` es el wrapper publico del modelo.
- `src/build_final_parquet.R` es el unico punto de entrada activo para materializar el parquet final desde datos raw.
- `src/graph.py`, `src/routing.py`, `src/ui.py` y `src/weights.py` quedan reservados para integrar el resto del proyecto.

## Superficie publica

`src/model.py` expone:

- `build_final_parquet(...)`
- `build_training_xy(...)`
- `build_and_train_model(...)`
- `train_model(X, y)`

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

- `build_final_parquet(accidents_csv_path, output_parquet_path=None, network_zip_path=None, force=False)`

Version mas directa para construir y entrenar:

- `build_and_train_model(accidents_csv_path, output_parquet_path=None, network_zip_path=None, force=False)`

Inputs locales esperados:

- CSV de accidentes
- opcionalmente un zip de red OSM para enriquecer el matching y las features exogenas

Si `Rscript` no esta disponible o falta algun input, `src/model.py` devuelve un error claro.

## Rol de model.py

`src/model.py` queda reducido a lo imprescindible:

1. materializar el parquet con el script de R
2. convertir el parquet a `X` e `y`
3. entrenar el modelo

## Comparativa de modelos

La comparativa reproducible entre `Negative Binomial` y `Poisson` vive en:

- `analysis/model.ipynb`

Ese notebook es el artefacto activo para:

1. configurar las rutas locales de entrada
2. construir o reutilizar el parquet final
3. aplicar el split temporal `2016-2022 / 2023 / 2024`
4. entrenar ambos modelos
5. reportar `mean_poisson_deviance`, `MAE` y `RMSE`

Notas operativas:

- el repo no versiona `data/` ni `outputs/`
- quien ejecute el notebook debe rellenar `ACCIDENTS_CSV_PATH` y, si hace falta, `NETWORK_ZIP_PATH`
- en Windows, si arrancas Jupyter desde terminal, usa `py -3 -m jupyter lab` o `py -3 -m notebook`
