# Nota del Modelo

## Estructura

El modelo queda concentrado en:

- `src/model.py`

La comparacion de modelos queda fuera de `src`, en:

- `analysis/model.ipynb`

No se usan scripts auxiliares dentro de `src`: el codigo del modelo queda concentrado en `model.py`.

## Que hace `model.py`

`model.py` contiene las funciones para:

- leer y preparar `accidentes_con_trafico_final.csv`;
- normalizar clima y calle;
- crear variables temporales;
- convertir coordenadas UTM a lat/lon;
- crear `accident_count`;
- crear filas con `accident_count = 0`;
- entrenar modelos de conteo;
- guardar y cargar modelos `.pkl`;
- predecir y evaluar.

## Unidad de entrenamiento

Cada fila representa:

- calle normalizada;
- franja horaria de 4 horas;
- fin de semana o no;
- festivo o no;
- clima.

En la evaluacion temporal se anade `analysis_year` solo para separar train, validation y test.

## Variables del modelo

Categoricas:

- `temporal_bin_4h`
- `weather`

Numericas:

- `lat`
- `lon`
- `is_weekend`
- `is_holiday`
- `intensidad`
- `ocupacion`
- `vmed`
- `street_accident_prior`

`street_key` no entra como categoria directa. Se resume en `street_accident_prior`.

## Entrenamiento

```python
from src.model import train_final_model

model, table = train_final_model("accidentes_con_trafico_final.csv", max_streets=1500)
```

El modelo final usa `Negative Binomial`, porque el target es un conteo no negativo con muchos ceros.

## Comparacion

El notebook `analysis/model.ipynb` compara:

- baseline global;
- Poisson con clima;
- Negative Binomial sin clima;
- Negative Binomial con clima.

Usa split temporal:

- train: `2016-2022`;
- validation: `2023`;
- test: `2024`.

## Fuera de esta fase

- No se conecta aun con `service.py`.
- No se toca Flask.
- No se toca Dijkstra.
- No se toca OpenMeteo.
- No se suben el CSV, `models/` ni `outputs/`.
