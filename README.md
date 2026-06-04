# Proyecto_iii

Aplicacion de rutas seguras en Madrid. La app y el modelo siguen separados.

## Modelo

Todo lo necesario del modelo esta en:

- `src/model.py`

Ese archivo contiene:

- preparacion del CSV;
- normalizacion de calle y clima;
- creacion de variables;
- construccion de tabla de entrenamiento;
- entrenamiento de Negative Binomial y Poisson;
- prediccion;
- conversion a riesgo `0-10`;
- guardado, carga y testeo.

El flujo activo de modelo parte del CSV local y se llama desde funciones de Python.

## Entrenar desde Python

```python
from src.model import train_final_model, save_model

model, table = train_final_model("accidentes_con_trafico_final.csv", max_streets=1500)
save_model(model, "models/risk_negative_binomial.pkl")
```

## Comparacion de modelos

La comparacion y analisis no estan en `src`. Estan en:

- `analysis/model.ipynb`

El notebook compara:

- baseline global;
- Poisson con clima;
- Negative Binomial sin clima;
- Negative Binomial con clima.

## Variables usadas

- `temporal_bin_4h`
- `weather`
- `lat`
- `lon`
- `is_weekend`
- `is_holiday`
- `intensidad`
- `ocupacion`
- `vmed`
- `street_accident_prior`

El target es:

- `accident_count`

## Archivos locales no versionados

- `accidentes_con_trafico_final.csv`
- `models/`
- `outputs/`
