# Proyecto_iii

Desarrollamos una aplicación que ofrece rutas por carretera desde un punto de origen hasta uno de destino (elegidos por el usuario) teniendo en cuenta el riesgo de accidente en cada calle y ofreciendo alternativas tan seguras como especifique el usuario.

## Metodología

Llevamos a cabo varios análisis previos para desarrollar un modelo de cálculo de riesgo por calle basado en factores dinámicos (clima, hora, día...) y estáticos (distancia, límite de velocidad...).

Con el modelo desarrollado predecimos los valores de riesgo de las calles y ponderamos el peso de cada una en el grafo que modela la ciudad según la importancia del riesgo para el usuario (a mayor importancia, mayor influencia del riesgo en los pesos de las calles, el camino más rápido suele tener más accidentes y seguramente se sugiera un camino más lento al tener en cuenta los valores de riesgo).

Finalmente, se representa el grafo sobre un mapa y se ofrece al usuario la opción de elegir origen, destino e importancia del riesgo para las rutas sugeridas.

## Modelo

Todo lo necesario del modelo esta en:

- `src/model.py`

El archivo contiene:

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


# Observaciones

Proyecto llevado a cabo por 6 estudiantes del grado de Ciencia de Datos en la Universidad Politécnica de Valencia en el marco de la asignatura "Proyecto III" de tercer curso.

Con objeto de su evaluación, se pone a la disposición de cualquier usuario interesado en probarla en el siguiente enlace: saferoute.pocoloco.dev