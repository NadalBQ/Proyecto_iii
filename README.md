# Proyecto_iii

Desarrollamos una aplicacion que ofrece rutas por carretera desde un punto de origen hasta uno de destino, teniendo en cuenta el riesgo de accidente en cada calle y ofreciendo alternativas tan seguras como especifique el usuario.

## Metodologia

Llevamos a cabo analisis previos para desarrollar un modelo de calculo de riesgo por calle basado en factores dinamicos, como hora y dia, y factores estaticos, como distancia, limite de velocidad y caracteristicas de la via.

Con el modelo desarrollado se predicen valores de riesgo de las calles y se pondera el peso de cada una en el grafo de la ciudad segun la importancia del riesgo para el usuario.

Finalmente, se representa la ruta sobre un mapa y se ofrece al usuario la opcion de elegir origen, destino e importancia del riesgo.

## Componentes principales

- `main.py` contiene el CLI de SafeRoute.
- `src/ui.py` contiene la interfaz Flask.
- `src/service.py` conecta la entrada de usuario, el grafo, el modelo y el calculo de ruta.
- `src/model.py` es el wrapper publico del modelo.
- `src/build_final_parquet.R` materializa el parquet final desde datos raw.

## Superficie publica del modelo

`src/model.py` expone:

- `build_final_parquet(...)`
- `build_training_xy(...)`
- `build_and_train_model(...)`
- `train_model(X, y)`
- `load_model(path)`
- `save_model(model, path)`
- `predict(model, X)`
- `test_model(model, X, y)`

## Dataset final de modelado

El parquet final sigue siendo:

- `training_table_with_exogenous_context_features.parquet`

Contrato activo:

- target: `accident_count`
- unidad observacional: `edge_id + analysis_year + temporal_bin_4h + is_weekend`

## Materializacion del parquet

Toda la logica activa de `raw -> parquet` queda unificada en:

- `src/build_final_parquet.R`

Desde Python, la llamada publica es:

- `build_final_parquet(accidents_csv_path, output_parquet_path=None, network_zip_path=None, force=False)`

Version directa para construir y entrenar:

- `build_and_train_model(accidents_csv_path, output_parquet_path=None, network_zip_path=None, force=False)`

Inputs locales esperados:

- CSV de accidentes
- opcionalmente un zip de red OSM para enriquecer el matching y las features exogenas

## Observaciones

Proyecto en desarrollo.

Proyecto llevado a cabo por 6 estudiantes del grado de Ciencia de Datos en la Universidad Politecnica de Valencia.
