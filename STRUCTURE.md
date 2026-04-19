# Project Structure

## Root

- `main.py`: orquestador visible. Carga argumentos, lee/escribe tablas y llama a `src/model.py`.
- `README.md`: contrato corto de uso del repo.
- `STRUCTURE.md`: explicación breve de qué hace cada archivo y por qué existe.
- `requirements.txt`: dependencias Python del runtime.
- `analysis/`: contexto metodológico. No forma parte del flujo de ejecución.

## src

- `model.py`: fichero principal del modelo. Contiene carga, guardado, entrenamiento, actualización, predicción, test y helpers internos del `negative_binomial_b4`.
- `graph.py`: placeholder del bloque de grafo del proyecto.
- `routing.py`: placeholder del bloque de routing del proyecto.
- `ui.py`: placeholder del bloque de interfaz del proyecto.
- `weights.py`: placeholder del bloque de pesos/contexto del proyecto.

## Runtime local

El código usa estas rutas locales, pero no se versionan:

- `artifacts/negative_binomial_b4.pkl`
- `outputs/modeling/training_table_with_exogenous_context_features.parquet`

Significado:

- `train` y `update` parten del parquet final externo
- `predict` y `evaluate` parten del `.pkl` externo

## Modelo activo

- modelo final: `negative_binomial_b4`
- target: `accident_count`
- no hay clasificación
- no se usa `accuracy_score`
