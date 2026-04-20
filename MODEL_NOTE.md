# Nota del Modelo

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

En la validacion actual:

- media del target = `0.0411`
- varianza del target = `0.0525`
- ratio varianza/media = `1.2753`

Esto sugiere una sobredispersion moderada, lo que apoya el uso de Negative Binomial como modelo final razonable.

## Por que no regresion lineal

La regresion lineal se utilizo solo como baseline debil.
No es la familia natural para targets de conteo escasos y no negativos, y no incorpora supuestos especificos de datos de conteo.
Por eso sirve como punto de comparacion, pero no como la familia preferente para el sistema final.

## Por que no quedarse en Poisson

Poisson sigue siendo un baseline importante y se evaluo explicitamente.
Sin embargo, si los datos presentan sobredispersion, una especificacion puramente Poisson puede ser demasiado restrictiva.
Negative Binomial mantiene la estructura de modelo de conteo y permite mas flexibilidad en la dispersion.

En los resultados actuales, Negative Binomial mejora ligeramente a Poisson en mean Poisson deviance, lo que es coherente con esa motivacion.

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

## Resultados actuales

La comparacion actual se hizo entre:

- `negative_binomial`
- `poisson`
- `linear_regression`

### Validation

- Negative Binomial: mean Poisson deviance = `0.225692`, MAE = `0.063397`, RMSE = `0.203093`
- Poisson: mean Poisson deviance = `0.226390`, MAE = `0.062585`, RMSE = `0.203082`
- Linear Regression: mean Poisson deviance = `0.298942`, MAE = `0.065167`, RMSE = `0.204344`

### Test

- Negative Binomial: mean Poisson deviance = `0.286206`, MAE = `0.073541`, RMSE = `0.235798`
- Poisson: mean Poisson deviance = `0.288569`, MAE = `0.072658`, RMSE = `0.235880`
- Linear Regression: mean Poisson deviance = `0.402903`, MAE = `0.074454`, RMSE = `0.236843`

## Interpretacion

Los resultados apoyan tres conclusiones directas:

1. Los modelos de conteo son mas apropiados que la regresion lineal para este problema.
2. Negative Binomial y Poisson rinden de forma parecida, pero Negative Binomial es ligeramente mejor en la metrica principal orientada a conteos.
3. La mejora de Negative Binomial sobre Poisson es pequena, lo cual es coherente con que la sobredispersion exista pero no sea extrema.

Esto hace que Negative Binomial sea una eleccion final defendible: sigue siendo interpretable, operativamente simple y ligeramente mas robusto que Poisson bajo el patron de dispersion observado.

## Referencias que puedes citar

### Referencias metodologicas principales

- Cameron, A. C., & Trivedi, P. K. (2013). *Regression Analysis of Count Data* (2nd ed.). Cambridge University Press. https://cameron.econ.ucdavis.edu/racd2/
- Hilbe, J. M. (2011). *Negative Binomial Regression* (2nd ed.). Cambridge University Press. https://www.cambridge.org/tg/titles/negative-binomial-regression-2nd-edition

### Referencias de implementacion

- statsmodels. *NegativeBinomial*. https://www.statsmodels.org/stable/generated/statsmodels.discrete.discrete_model.NegativeBinomial.html
- statsmodels. *Poisson family*. https://www.statsmodels.org/stable/generated/statsmodels.genmod.families.family.Poisson.html
- scikit-learn. *mean_poisson_deviance*. https://scikit-learn.org/stable/modules/generated/sklearn.metrics.mean_poisson_deviance.html
- scikit-learn. *LinearRegression*. https://sklearn.org/stable/modules/generated/sklearn.linear_model.LinearRegression.html

## Version corta para la memoria

Negative Binomial se selecciono porque el target es un conteo escaso y no negativo, y los datos muestran sobredispersion moderada, lo que lo hace mas apropiado que la regresion lineal y ligeramente mas flexible que un modelo puramente Poisson.
La evaluacion se realizo con un split temporal (2016-2022 train, 2023 validation, 2024 test), usando mean Poisson deviance como metrica principal y MAE/RMSE como metricas complementarias.
En la comparacion final, Negative Binomial mejoro ligeramente a Poisson y supero claramente a la regresion lineal en mean Poisson deviance.
