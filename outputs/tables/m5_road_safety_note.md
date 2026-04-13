# M5 - Nota Tecnica ROAD-SAFETY

- El baseline principal se ejecuta sobre 2020-2024 con `intensidad, ocupacion, hour_sin, hour_cos`.
- El PCA se ha usado como detector exploratorio de redundancias y bloques latentes, no como definicion final de riesgo.
- `intensidad` y `ocupacion` aparecen como un bloque de trafico/condicion de circulacion suficientemente proximo como para evitar sobreponderarlas juntas sin control.
- `hour_sin` y `hour_cos` estructuran el bloque temporal; deben tratarse como codificacion conjunta del ciclo horario y no como dos senales independientes a sobreponderar por separado.
- `vmed` modifica la estructura solo como sensibilidad y permanece bajo revision metodologica; no debe entrar en el baseline del indice.
- `is_weekend` puede servir para contraste, pero su papel es de sensibilidad y no de nucleo del bloque continuo principal.
- Para el indice futuro, la traduccion razonable es trabajar por bloques interpretables: bloque de trafico (`intensidad`, `ocupacion`), bloque temporal (hora codificada en seno/coseno) y variables bajo revision aparte.
- Una implementacion posterior del indice deberia evitar sumar con peso pleno variables del mismo bloque sin una regla explicita de control de redundancia.
