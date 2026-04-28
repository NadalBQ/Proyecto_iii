# Nota del Modelo

## Estado actual del repo

`src/model.py` contiene la API minima del modelo final:

- materializar el parquet
- convertir el parquet a `X` e `y`
- entrenar el modelo final `Negative Binomial`

La comparativa reproducible entre `Negative Binomial` y `Poisson` vive en `analysis/model.ipynb`.
Ese notebook usa rutas locales configuradas al inicio y no depende de datos versionados dentro del repo.
Por eso, las metricas exactas dependen del dataset local usado en cada ejecucion.

## Que se ha modelado

La tabla activa de modelado es `training_table_with_exogenous_context_features.parquet`.
Cada observacion corresponde a un segmento de via bajo un contexto temporal concreto:

- `edge_id`
- `analysis_year`
- `temporal_bin_4h`
- `is_weekend`

La variable objetivo es `accident_count`, definida como el numero observado de accidentes emparejados y agregados a ese nivel de panel.

## Por que Negative Binomial

La respuesta es un conteo escaso y no negativo, asi que un modelo de conteo es mas apropiado que una regresion lineal estandar.
Poisson es el baseline natural para datos de conteo, pero asume que la media condicional y la varianza condicional son de magnitud similar.
Cuando existe sobredispersion, Negative Binomial es una extension estandar porque relaja la restriccion de varianza propia de Poisson.

Si en una ejecucion local la varianza del target supera de forma apreciable a la media, eso apunta a sobredispersion y refuerza el uso de Negative Binomial como modelo final razonable.

## Por que no quedarse en Poisson

Poisson sigue siendo un baseline importante y se evaluo explicitamente.
Sin embargo, si los datos presentan sobredispersion, una especificacion puramente Poisson puede ser demasiado restrictiva.
Negative Binomial mantiene la estructura de modelo de conteo y permite mas flexibilidad en la dispersion.

Cuando la sobredispersion existe pero no es extrema, es normal que Negative Binomial y Poisson rindan de forma parecida, con una ligera ventaja para Negative Binomial en metricas orientadas a conteos.

## Por que estas metricas

La metrica principal de evaluacion es `mean_poisson_deviance`.
Esta metrica esta alineada con prediccion de conteos y es mas informativa para este problema que depender solo de metricas de error cuadratico.

Ademas se reportan dos metricas complementarias:

- `MAE`
- `RMSE`

Se mantienen como resumenes adicionales del error, pero no como la base principal para justificar la eleccion del modelo.

## Protocolo de evaluacion

La evaluacion siguio un split temporal estricto:

- train: `2016-2022`
- validation: `2023`
- test: `2024`

Esto evita leakage aleatorio entre periodos y es mas coherente con el objetivo de prediccion futura del sistema.

## Comparativa reproducible en el repo

La comparativa activa del repo se hace entre:

- `negative_binomial`
- `poisson`

El flujo reproducible es:

1. configurar rutas locales de entrada en `analysis/model.ipynb`
2. materializar o reutilizar `training_table_with_exogenous_context_features.parquet`
3. separar `train (2016-2022)`, `validation (2023)` y `test (2024)`
4. entrenar `Negative Binomial` y `Poisson`
5. reportar `mean_poisson_deviance`, `MAE` y `RMSE` en validation y test

Como los datos raw y el parquet generado no estan versionados en el repo, los valores numericos concretos no se fijan aqui como si fueran resultados universales.
La tabla exacta depende del CSV local configurado al ejecutar el notebook.

## Interpretacion

Los resultados apoyan tres conclusiones directas:

1. Los modelos de conteo son mas apropiados que usar una regresion lineal estandar para este problema.
2. Negative Binomial y Poisson deben compararse con la misma particion temporal y las mismas metricas.
3. Si la sobredispersion es real, Negative Binomial suele ser una opcion final mas flexible que un Poisson puro.

Esto hace que Negative Binomial sea una eleccion final defendible: sigue siendo interpretable, operativamente simple y ligeramente mas robusto que Poisson bajo el patron de dispersion observado.

## Referencias que puedes citar

### Referencias metodologicas principales

- Cameron, A. C., & Trivedi, P. K. (2013). *Regression Analysis of Count Data* (2nd ed.). Cambridge University Press. https://cameron.econ.ucdavis.edu/racd2/
- Hilbe, J. M. (2011). *Negative Binomial Regression* (2nd ed.). Cambridge University Press. https://www.cambridge.org/tg/titles/negative-binomial-regression-2nd-edition

### Referencias de implementacion

- statsmodels. *NegativeBinomial*. https://www.statsmodels.org/stable/generated/statsmodels.discrete.discrete_model.NegativeBinomial.html
- statsmodels. *Poisson family*. https://www.statsmodels.org/stable/generated/statsmodels.genmod.families.family.Poisson.html
- scikit-learn. *mean_poisson_deviance*. https://scikit-learn.org/stable/modules/generated/sklearn.metrics.mean_poisson_deviance.html

## Version corta para la memoria

Negative Binomial se selecciono porque el target es un conteo escaso y no negativo, y cuando los datos muestran sobredispersion resulta mas flexible que un modelo puramente Poisson.
La evaluacion se realiza con un split temporal (2016-2022 train, 2023 validation, 2024 test), usando mean Poisson deviance como metrica principal y MAE/RMSE como metricas complementarias.
La comparacion reproducible con Poisson queda centralizada en `analysis/model.ipynb`, y sus valores exactos dependen del dataset local configurado en esa ejecucion.
