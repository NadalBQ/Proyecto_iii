# Proyecto_iii

Desarrollamos una aplicación que ofrece rutas por carretera desde un punto de origen hasta uno de destino (elegidos por el usuario) teniendo en cuenta el riesgo de accidente en cada calle y ofreciendo alternativas tan seguras como especifique el usuario.

## Metodología

Llevamos a cabo varios análisis previos para desarrollar un modelo de cálculo de riesgo por calle basado en factores dinámicos (clima, hora, día...) y estáticos (distancia, límite de velocidad...).

Con el modelo desarrollado predecimos los valores de riesgo de las calles y ponderamos el peso de cada una en el grafo que modela la ciudad según la importancia del riesgo para el usuario (a mayor importancia, mayor influencia del riesgo en los pesos de las calles, el camino más rápido suele tener más accidentes y seguramente se sugiera un camino más lento al tener en cuenta los valores de riesgo).

Finalmente, se representa el grafo sobre un mapa y se ofrece al usuario la opción de elegir origen, destino e importancia del riesgo para las rutas sugeridas.

## Observaciones

Proyecto en desarrollo.

Proyecto llevado a cabo por 6 estudiantes del grado de Ciencia de Datos en la Universidad Politécnica de Valencia.