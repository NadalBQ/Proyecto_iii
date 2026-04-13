# ROAD-SAFETY — PLANS.md

Use this file for any task that is multi-step, architectural, risky, or likely to touch several files.

## When a plan is required

A written plan is required before implementation when the task involves any of the following:
- creating or changing repository structure,
- building a cleaning pipeline,
- changing the analytical methodology,
- introducing a new dependency,
- implementing graph/routing modules,
- creating API structure,
- or editing more than one core file.

## Required plan format

Every plan must contain these sections:

### 1. Objective
State the technical objective clearly.

### 2. Why this matters for ROAD-SAFETY
Connect the task to the end goal:
risk modeling, graph weighting, routing, or API readiness.

### 3. Files involved
List files to read, create, or modify.

### 4. Assumptions
List explicit assumptions.
Do not hide assumptions.

### 5. Milestones
Break the work into concrete milestones.

For each milestone include:
- purpose
- files touched
- expected output
- validation

### 6. Risks
List methodological or technical risks.

### 7. Done criteria
Define what must be true for the task to count as complete.

### 8. Open questions
List uncertainties that may need user confirmation.

## Implementation rules after planning

- Do not implement the entire plan at once unless the user explicitly asks for it.
- Prefer milestone-by-milestone execution.
- After each milestone, summarize:
  - what changed,
  - what was validated,
  - what remains pending.

## Analysis-specific rule

For data-analysis tasks, the plan must state:
- analytical unit,
- deduplication logic,
- missing-data treatment,
- variable selection criteria,
- and how findings will inform the later risk score or routing system.

## Refactoring rule

Do not refactor unrelated code while implementing a plan.
Keep the scope narrow.

## Active Plan - Traffic 2024 Pilot Aggregation (R Only)

### 1. Objective
Construir una capa resumida y usable de trafico historico de Madrid usando solo enero, abril, julio y octubre de 2024, con union a sensores oficiales y cuantificacion del solape con los sensores presentes en accidentes.

### 2. Why this matters for ROAD-SAFETY
Esta fase no entra en modelado ni routing. Su utilidad es cerrar un piloto pequeno y auditable de trafico historico real que permita evaluar si la infraestructura oficial de sensores puede aportar contexto exogeno reutilizable para ROAD-SAFETY.

### 3. Files involved
Read:
- `data/raw/traffic_sensor_locations/sensor_locations.csv`
- `data/raw/traffic_history_2024/01-2024.csv`
- `data/raw/traffic_history_2024/04-2024.csv`
- `data/raw/traffic_history_2024/07-2024.csv`
- `data/raw/traffic_history_2024/10-2024.csv`
- `data/raw/accidents/accidentes_con_trafico_final.csv`

Create:
- `scripts/traffic/01_inspect_traffic_inputs.R`
- `scripts/traffic/02_build_traffic_2024_4months_panel.R`
- `scripts/traffic/03_join_traffic_sensor_locations.R`
- `scripts/traffic/04_accident_sensor_overlap.R`
- `data/processed/traffic_2024_4months_sensor_panel.csv`
- `data/processed/traffic_2024_4months_aggregated.csv`
- `data/processed/traffic_2024_4months_aggregated_accident_sensor_subset.csv`
- `outputs/traffic_aggregation_summary.csv`
- `outputs/traffic_accident_sensor_overlap_summary.csv`
- `outputs/traffic_data_quality_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- La clave candidata compartida entre trafico, sensores y accidentes es `id` / `id_sensor_cercano`.
- Los cuatro meses de trafico comparten el mismo schema logico aunque octubre tenga una irregularidad menor en el header.
- El fichero de accidentes debe usarse aqui solo para auditar sensores, no para rehacer fases antiguas del proyecto.
- El producto final de esta fase debe ser pequeno y agregable; el panel observacional solo se guarda como intermedio limpio y reutilizable.

### 5. Milestones
- M1. Inspeccion de inputs.
  Purpose: detectar separadores, columnas clave, posibles tipos y riesgos de parsing.
  Files touched: `scripts/traffic/01_inspect_traffic_inputs.R`
  Expected output: diagnostico reproducible por consola.
  Validation: los seis inputs existen y las columnas clave quedan identificadas.

- M2. Construccion del panel limpio de 4 meses.
  Purpose: normalizar nombres, parsear fecha/hora y derivar variables temporales.
  Files touched: `scripts/traffic/02_build_traffic_2024_4months_panel.R`
  Expected output: `traffic_2024_4months_sensor_panel.csv`
  Validation: solo se procesan enero/abril/julio/octubre 2024 y el panel contiene `sensor_id`, `analysis_year`, `month`, `hour`, `temporal_bin_4h`, `is_weekend`.

- M3. Agregacion y union con sensores oficiales.
  Purpose: producir una tabla agregada pequena y enriquecerla con metadata de sensores.
  Files touched: `scripts/traffic/03_join_traffic_sensor_locations.R`
  Expected output: `traffic_2024_4months_aggregated.csv`, `traffic_aggregation_summary.csv`
  Validation: la agregacion queda a nivel `sensor_id + analysis_year + month + temporal_bin_4h + is_weekend` y la union documenta la clave usada.

- M4. Solape con sensores de accidentes.
  Purpose: cuantificar overlap real entre accidentes, sensores oficiales y trafico agregado.
  Files touched: `scripts/traffic/04_accident_sensor_overlap.R`
  Expected output: `traffic_2024_4months_aggregated_accident_sensor_subset.csv`, `traffic_accident_sensor_overlap_summary.csv`, `traffic_data_quality_note.md`
  Validation: se cuantifican sensores unicos y porcentajes de overlap sin ocultar coberturas malas.

### 6. Risks
- El solape entre sensores de accidentes y sensores oficiales puede ser bajo o nulo.
- El fichero de accidentes usa un separador distinto y puede requerir encoding UTF-8 explicito.
- La cabecera de octubre no esta formateada igual que las otras, aunque parece el mismo schema.
- Pueden existir sensores oficiales duplicados por `id`; si ocurre, la clave de union debe documentarse y no forzarse.

### 7. Done criteria
- Los cuatro meses quedan procesados y agregados.
- Existe una tabla final pequena y usable con metadata de sensores cuando el join es fiable.
- Existe una tabla subset para sensores presentes en accidentes.
- El overlap queda cuantificado y documentado.
- No se toca modelado, routing ni otras fases del proyecto.

### 8. Open questions
- Ninguna para esta fase piloto; si el overlap sale malo, se documenta y se cierra la fase sin forzar integraciones.

## Active Plan - Missing Accident Sensor Coverage Audit

### 1. Objective
Auditar el impacto real de los sensores presentes en accidentes que no aparecen en la capa piloto de trafico 2024 ya agregada, sin reprocesar meses ni abrir nuevas fases.

### 2. Why this matters for ROAD-SAFETY
Antes de reutilizar la capa piloto de trafico como contexto exogeno futuro, hace falta saber si el gap de cobertura detectado es operativamente asumible o si puede sesgar demasiado una integracion posterior.

### 3. Files involved
Read:
- `data/raw/accidents/accidentes_con_trafico_final.csv`
- `data/processed/traffic_2024_4months_aggregated.csv`
- `data/processed/traffic_2024_4months_sensor_panel.csv`
- `data/processed/traffic_2024_4months_aggregated_accident_sensor_subset.csv`
- `outputs/traffic_accident_sensor_overlap_summary.csv`
- `data/raw/traffic_sensor_locations/sensor_locations.csv` (support only if present)

Create:
- `scripts/traffic/05_audit_missing_accident_sensor_coverage.R`
- `outputs/missing_accident_sensors_list.csv`
- `outputs/missing_accident_sensor_impact_summary.csv`
- `outputs/missing_accident_sensor_impact_note.md`
- `outputs/missing_accident_sensor_top_contributors.csv`

Modify:
- `PLANS.md`

### 4. Assumptions
- La clave comparativa valida sigue siendo `id_sensor_cercano` en accidentes frente a `sensor_id` en la tabla agregada de trafico.
- El impacto que interesa en esta fase es sobre filas de accidentes, no sobre modelado ni sobre edge_id.
- El gap debe evaluarse con la capa piloto ya cerrada, no ampliando meses.

### 5. Milestones
- M1. Identificar sensores faltantes exactos.
  Purpose: derivar el set de sensores en accidentes que no tiene cobertura en la tabla agregada.
  Files touched: `scripts/traffic/05_audit_missing_accident_sensor_coverage.R`
  Expected output: `missing_accident_sensors_list.csv`
  Validation: el numero de sensores faltantes cuadra con el overlap previo.

- M2. Cuantificar impacto real en filas de accidentes.
  Purpose: medir filas afectadas, porcentaje y desgloses basicos por ano, distrito y franja horaria.
  Files touched: `scripts/traffic/05_audit_missing_accident_sensor_coverage.R`
  Expected output: `missing_accident_sensor_impact_summary.csv`
  Validation: covered rows + missing rows = total accident rows con sensor.

- M3. Concentracion del gap y nota operativa.
  Purpose: evaluar si pocos sensores concentran gran parte del problema y emitir recomendacion concreta.
  Files touched: `scripts/traffic/05_audit_missing_accident_sensor_coverage.R`
  Expected output: `missing_accident_sensor_top_contributors.csv`, `missing_accident_sensor_impact_note.md`
  Validation: la recomendacion se apoya en metricas observadas y no abre nuevas fases.

### 6. Risks
- El gap puede estar muy concentrado y ser mas relevante de lo que sugiere el simple 92.44% de overlap.
- El CSV de accidentes usa coma y puede requerir UTF-8 explicito.
- Algunas distribuciones opcionales pueden ser ruidosas si se basan en filas y no en expedientes; se documentan como descriptivas, no causales.

### 7. Done criteria
- Existe un listado explicito de sensores faltantes.
- El impacto sobre filas de accidentes queda cuantificado.
- Existe un top de sensores faltantes por contribucion al gap.
- Hay una recomendacion operativa clara sobre si la cobertura actual permite seguir adelante en una integracion piloto.
- No se reabre el procesamiento de trafico ni se entra en modelado, routing o edge mapping.

### 8. Open questions
- Ninguna para esta auditoria; si el gap sale alto se documenta como recomendacion, no como nueva implementacion automatica.

## Active Plan - Traffic Pilot Integration to Accidents

### 1. Objective
Construir una integracion piloto `traffic -> accidentes` a nivel fila raw de `accidentes_con_trafico_final.csv` mediante left join, sin perder filas, sin deduplicar y clasificando explicitamente los no-match segun su razon metodologica.

### 2. Why this matters for ROAD-SAFETY
El proyecto necesita comprobar si la capa piloto de trafico ya puede incorporarse como contexto parcial y auditable. Esta fase no entra en modelado ni routing; solo deja una integracion reusable y correctamente interpretada como cobertura parcial.

### 3. Files involved
Read:
- `data/raw/accidents/accidentes_con_trafico_final.csv`
- `data/processed/traffic_2024_4months_aggregated.csv`
- `data/processed/traffic_2024_4months_sensor_panel.csv`
- `data/processed/traffic_2024_4months_aggregated_accident_sensor_subset.csv`
- `outputs/traffic_aggregation_summary.csv`
- `outputs/traffic_accident_sensor_overlap_summary.csv`
- `outputs/traffic_data_quality_note.md`
- `outputs/missing_accident_sensors_list.csv`
- `outputs/missing_accident_sensor_impact_summary.csv`
- `outputs/missing_accident_sensor_top_contributors.csv`
- `outputs/missing_accident_sensor_impact_note.md`

Create:
- `scripts/traffic/06_integrate_traffic_pilot_to_accidents.R`
- `data/processed/traffic_2024_4months_accident_joined.csv`
- `data/processed/traffic_2024_4months_model_ready.csv`
- `outputs/traffic_2024_4months_join_quality_summary.csv`
- `outputs/traffic_2024_4months_join_missing_reasons.csv`
- `outputs/traffic_2024_4months_pilot_period_coverage_summary.csv`
- `outputs/traffic_2024_4months_integration_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- La clave de sensor valida sigue siendo `id_sensor_cercano -> sensor_id` con normalizacion numerica explicita.
- La tabla `traffic_2024_4months_aggregated.csv` es la fuente correcta para el join y debe ser unica por `sensor_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- La capa de trafico cubre solo 2024-01, 2024-04, 2024-07 y 2024-10; por tanto, gran parte de los no-match del historico de accidentes son missing esperados por cobertura temporal parcial.

### 5. Milestones
- M1. Auditar inputs y validar unicidad del lado trafico.
  Purpose: asegurar que la clave de join es consistente y no duplicara filas de accidentes.
  Files touched: `scripts/traffic/06_integrate_traffic_pilot_to_accidents.R`
  Expected output: chequeos reproducibles por consola y stop si la clave de trafico no es unica.
  Validation: cero duplicados en la clave del trafico agregado.

- M2. Implementar left join y clasificacion de estados.
  Purpose: integrar trafico a accidentes sin perder filas y distinguir razones de no-match.
  Files touched: `scripts/traffic/06_integrate_traffic_pilot_to_accidents.R`
  Expected output: `traffic_2024_4months_accident_joined.csv`
  Validation: filas antes y despues del join iguales; dataset de accidentes no deduplicado.

- M3. Preparar subconjunto model-ready y resumentes auditables.
  Purpose: dejar una salida piloto reutilizable y cubrir calidad de join global y dentro del periodo piloto.
  Files touched: `scripts/traffic/06_integrate_traffic_pilot_to_accidents.R`
  Expected output: `traffic_2024_4months_model_ready.csv`, summaries y nota metodologica.
  Validation: cobertura global y dentro del piloto cuantificadas; missing reasons pobladas.

### 6. Risks
- Confundir no-match fuera del periodo piloto con fallo de join.
- Duplicar filas si la tabla de trafico agregado no es unica por clave.
- Tratar una salida raw-row como si fuese una tabla deduplicada a nivel accidente.
- Sobreinterpretar la cobertura global del dataset cuando el trafico solo cubre 4 meses de 2024.

### 7. Done criteria
- Existe un left join desde accidentes que conserva todas las filas.
- `traffic_missing_reason` clasifica matched y no-match con logica explicita.
- La cobertura queda cuantificada tanto globalmente como dentro del periodo piloto.
- La salida queda documentada como capa parcial y no como integracion historica completa ni capa final de routing.

### 8. Open questions
- Ninguna para esta fase; si la cobertura dentro del piloto sale insuficiente, se documenta pero no se abre automaticamente una ampliacion de periodo.

## Active Plan - Traffic Pilot Integration to Model Unit

### 1. Objective
Construir una tabla piloto de integracion `trafico -> unidad del modelo`, restringida explicitamente a 2024 y a los meses 1, 4, 7 y 10, lista para una futura fase de reentrenamiento piloto pero sin entrenar nada todavia.

### 2. Why this matters for ROAD-SAFETY
El join `trafico -> accidentes` ya funciona como capa parcial. El siguiente paso razonable es dejar una unidad de modelado con trafico compatible con el pipeline espacial del proyecto, sin fingir cobertura completa del historico ni mezclarlo aun con routing final.

### 3. Files involved
Read:
- `data/processed/traffic_2024_4months_accident_joined.csv`
- `data/processed/traffic_2024_4months_model_ready.csv`
- `data/raw/accidents/accidentes_con_trafico_final.csv`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`

Create:
- `scripts/traffic/07_build_traffic_model_integration_pilot.R`
- `data/processed/traffic_2024_4months_model_integration_pilot.csv`
- `outputs/traffic_2024_4months_model_integration_summary.csv`
- `outputs/traffic_2024_4months_model_integration_missing_reasons.csv`
- `outputs/traffic_2024_4months_model_integration_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- `m9_accident_edge_matches.csv` aporta el enlace fiable `num_expediente -> edge_id` y es la via correcta para llevar el trafico piloto a una unidad por edge.
- El trafico piloto debe mantenerse a nivel mensual, por lo que la unidad piloto debe incluir `month` ademas de `temporal_bin_4h` e `is_weekend`.
- Las salidas M11/M12 se auditan para compatibilidad conceptual, pero no se usan como fuente directa de esta integracion piloto porque no aportan la misma granularidad mensual del trafico piloto.

### 5. Milestones
- M1. Auditar viabilidad de la unidad piloto.
  Purpose: confirmar que `edge_id + analysis_year + month + temporal_bin_4h + is_weekend` es enlazable sin forzar el pipeline.
  Files touched: `scripts/traffic/07_build_traffic_model_integration_pilot.R`
  Expected output: chequeos de integridad sobre `num_expediente -> edge_id`.
  Validation: `m9_accident_edge_matches.csv` unico por `num_expediente`.

- M2. Construir base piloto a nivel accidente dentro del periodo de trafico.
  Purpose: pasar de filas raw de accidentes a una base piloto por accidente sin perder trazabilidad de soporte ni de missing.
  Files touched: `scripts/traffic/07_build_traffic_model_integration_pilot.R`
  Expected output: dataset intermedio en memoria con `edge_id`, cobertura de trafico y flags de calidad.
  Validation: solo 2024 meses `1,4,7,10`; razones de no-cobertura separadas.

- M3. Agregar a unidad de modelado piloto y resumir cobertura.
  Purpose: producir la tabla final por unidad del modelo y resumentes auditables.
  Files touched: `scripts/traffic/07_build_traffic_model_integration_pilot.R`
  Expected output: `traffic_2024_4months_model_integration_pilot.csv` y summaries.
  Validation: cobertura medida dentro del piloto y dentro de la unidad final; `edge_id` auditado.

### 6. Risks
- El enlace por `num_expediente` puede dejar fuera accidentes piloto sin `edge_id`, lo que debe cuantificarse en vez de ocultarse.
- La agregacion de filas raw a accidente puede tener conflictos de clave interna; si aparecen, deben marcarse.
- La cobertura de trafico en la unidad final puede bajar respecto al 95.53% de la fase previa si la exigencia de `edge_id` elimina accidentes.

### 7. Done criteria
- Existe una tabla piloto por `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- La tabla esta restringida al periodo piloto de trafico.
- La cobertura dentro del piloto y las razones de no-cobertura quedan cuantificadas.
- La salida queda documentada como tabla lista para una siguiente fase piloto de modelado, no para routing final.

### 8. Open questions
- Ninguna para esta fase; si el enlace a `edge_id` reduce cobertura, se documenta como limitacion del piloto, no como nueva fase automatica.

## Active Plan - Traffic Pilot Training Table With Defensible Zeros

### 1. Objective
Construir una pilot training table restringida a 2024 meses 1, 4, 7 y 10, en la unidad `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`, incorporando trafico cuando exista y generando ceros defendibles sin expandir ciegamente toda la red.

### 2. Why this matters for ROAD-SAFETY
La siguiente fase del modelado piloto necesita una tabla con positivos y ceros en el mismo marco temporal del trafico. Esta fase no reentrena nada: deja una base reutilizable para comparar mas adelante un baseline piloto sin trafico frente a otro con trafico.

### 3. Files involved
Read:
- `data/processed/traffic_2024_4months_model_integration_pilot.csv`
- `data/processed/traffic_2024_4months_accident_joined.csv`
- `data/processed/traffic_2024_4months_aggregated.csv`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`

Create:
- `scripts/traffic/08_build_traffic_pilot_training_table.R`
- `data/processed/traffic_2024_4months_pilot_training_table.csv`
- `outputs/traffic_2024_4months_pilot_training_table_summary.csv`
- `outputs/traffic_2024_4months_pilot_training_table_missing_reasons.csv`
- `outputs/traffic_2024_4months_pilot_training_table_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- El universo espacial del piloto debe limitarse a los `edge_id` ya observados en la tabla piloto positiva, no a toda la red.
- La malla temporal valida debe venir de los bins realmente presentes en la capa agregada de trafico 2024 piloto.
- Las features historicas agregadas de M10/M11 que dependen del historico completo no deben entrar aqui como variables base si introducen leakage; solo se usaran atributos estaticos del edge cuando sean utiles.

### 5. Milestones
- M1. Auditar inputs y fijar regla de ceros.
  Purpose: confirmar universo de edges positivos, malla temporal piloto y posibilidad de propagar soporte de sensores a ceros.
  Files touched: `scripts/traffic/08_build_traffic_pilot_training_table.R`
  Expected output: chequeos internos del script.
  Validation: la malla temporal queda restringida a 2024 meses `1,4,7,10`.

- M2. Construir grid piloto y generar ceros defendibles.
  Purpose: crear unidades zero mediante `pilot_edge_universe x pilot_time_grid`, sin expandir toda la red.
  Files touched: `scripts/traffic/08_build_traffic_pilot_training_table.R`
  Expected output: `traffic_2024_4months_pilot_training_table.csv`
  Validation: la tabla contiene positivos y ceros, y cada cero lleva trazabilidad de generacion.

- M3. Integrar trafico y features base seguras.
  Purpose: llevar trafico agregado a todas las unidades donde haya soporte y anadir atributos estaticos del edge sin leakage.
  Files touched: `scripts/traffic/08_build_traffic_pilot_training_table.R`
  Expected output: summary, missing reasons y nota metodologica.
  Validation: cobertura de trafico usable cuantificada y razones de missing separadas.

### 6. Risks
- Generar ceros sobre todo el grafo inflaria artificialmente la tabla; por eso se restringe al universo de edges positivos del piloto.
- Propagar soporte `edge -> sensor` desde accidentes piloto es conservador pero parcial; edges sin soporte de sensor dentro del piloto quedaran sin trafico aunque existan en la red.
- Incluir scores historicos completos como features base introduciria leakage; deben excluirse salvo atributos estaticos.

### 7. Done criteria
- Existe una pilot training table con positivos y ceros.
- La tabla esta restringida al piloto temporal de trafico.
- Los ceros generados quedan trazados y justificados.
- La cobertura de trafico y las razones de missing quedan cuantificadas.
- La salida queda documentada como base para una siguiente fase piloto de reentrenamiento, no como tabla final del sistema.

### 8. Open questions
- Ninguna para esta fase; si la cobertura de trafico sobre los ceros resulta baja, se documenta como limitacion del piloto y no se fuerza una expansion de red o de meses.

## Active Plan - M7 Historico-Espacial Blueprint

### 1. Objective
Diseñar e implementar el blueprint tecnico de la fase historico_espacial que permita pasar de accidentes geolocalizados a una logica futura de riesgo por tramo/arista, sin implementar todavia routing ni coste final de grafo.

### 2. Why this matters for ROAD-SAFETY
El proyecto no termina en un indice conceptual por accidente/contexto. Para que ROAD-SAFETY pueda recomendar rutas mas seguras, hace falta una capa espacial que:
- asigne accidentes a una unidad de red util para routing,
- agregue evidencia historica por tramo,
- ajuste esa evidencia por exposicion cuando sea posible,
- y deje preparado el puente hacia edge weighting.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `pca_accidentes.R`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`
- `bases de datos/cartografia-base-comunicacions-comunicaciones.csv`
- `bases de datos/a05003423-clasificacion-del-tipos-de-vias-de-la-direccion-general-de-trafico-dgt-de-espana-istac-cl_dgt_tipos_vias.csv`

Create:
- `R/07_historico_espacial_blueprint.R`
- `outputs/tables/m7_spatial_input_registry.csv`
- `outputs/tables/m7_spatial_unit_options.csv`
- `outputs/tables/m7_spatial_pipeline_stages.csv`
- `outputs/tables/m7_spatial_missing_inputs.csv`
- `outputs/tables/m7_spatial_output_registry.csv`
- `outputs/tables/m7_file_structure_blueprint.csv`
- `outputs/tables/m7_spatial_validation_summary.csv`
- `outputs/tables/m7_spatial_blueprint.md`
- `outputs/data/m7_existing_spatial_sources_summary.csv`

Modify:
- `pca_accidentes.R`
- `PLANS.md`

### 4. Assumptions
- La tabla `accidentes_tabla_accidente_master.csv` ya representa la unidad accidente correcta por expediente y es el input valido para la fase espacial.
- Las coordenadas `coordenada_x_utm` / `coordenada_y_utm` del master sirven para geolocalizacion, pero todavia necesitan confirmacion formal de CRS antes de map-matching real.
- `id_sensor_cercano` no debe asumirse como join directo con `Id. Tram / Id. Tramo` sin una tabla puente o una validacion externa.
- El CSV `estat-transit-temps-real-estado-trafico-tiempo-real.csv` aporta segmentos contextuales utiles, pero no equivale todavia a una red routable completa de aristas.
- La unidad espacial final para routing debe ser una arista/tramo de red drivable; los segmentos de trafico o sensores pueden funcionar como capas auxiliares o unidades puente.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar el plan M7 y fijar el alcance: blueprint espacial, no routing.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan completo con objetivo, hitos, riesgos y criterios de done.
- Validation:
  El plan debe separar baseline/contextual, historico_espacial y peso operativo final.

#### Milestone 2
- Purpose:
  Perfilar inputs espaciales ya disponibles y distinguirlos de los inputs futuros obligatorios.
- Files touched:
  `R/07_historico_espacial_blueprint.R`
- Expected output:
  Registro de inputs existentes y faltantes, con rutas relativas, rol metodologico y estado.
- Validation:
  Debe detectar como existentes la tabla accidente master y el CSV de tramos de trafico; y como faltantes una red routable y una tabla puente de asignacion.

#### Milestone 3
- Purpose:
  Fijar la unidad espacial baseline recomendada y el pipeline de implementacion espacial.
- Files touched:
  `R/07_historico_espacial_blueprint.R`
- Expected output:
  Tabla de opciones de unidad espacial y tabla de etapas del pipeline.
- Validation:
  Debe justificar por que la unidad final recomendada es arista/tramo de red y por que un segmento derivado puede servir solo como unidad puente.

#### Milestone 4
- Purpose:
  Definir outputs intermedios y estructura de archivos recomendada para la siguiente fase de implementacion.
- Files touched:
  `R/07_historico_espacial_blueprint.R`
- Expected output:
  Registro de salidas intermedias y blueprint de estructura de archivos.
- Validation:
  Debe incluir, como minimo, accidente->edge matches, agregacion historica por edge, exposicion por edge y score historico preliminar por edge.

#### Milestone 5
- Purpose:
  Integrar M7 en el runner y dejar validacion automatica reproducible.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  Ejecucion de M7 desde VS Code/Rscript y resumen final de readiness espacial.
- Validation:
  El runner debe ejecutar M7 sin romper M1-M6 y debe informar claramente que el repo aun no esta listo para routing ni edge weighting final.

### 6. Risks
- Riesgo de CRS: accidentes y segmentos existentes no parecen estar en el mismo sistema de coordenadas.
- Riesgo de unidad incorrecta: usar un segmento de trafico o un sensor como si fuera la arista final del grafo.
- Riesgo de join debil: asumir equivalencia entre `id_sensor_cercano`, `Id. Tram` y edge del grafo sin crosswalk.
- Riesgo de exposicion ausente: un conteo bruto de accidentes por tramo no basta para riesgo operativo.
- Riesgo de sobremezclar capas: baseline/contextual, historico_espacial y peso final deben seguir separados.

### 7. Done criteria
- Existe un modulo M7 ejecutable desde `pca_accidentes.R`.
- Se generan artefactos M7 con inputs, unidad espacial recomendada, pipeline, salidas intermedias, estructura de archivos y validacion.
- Queda explicito que el bloque historico_espacial aun no es edge weighting final.
- Quedan explicitados los inputs faltantes que bloquean map-matching real y routing.

### 8. Open questions
- Que fuente de red viaria se usara como red routable canonica: OSMnx/OSM, cartografia municipal o una fusion de ambas.
- Si existe o puede construirse una tabla puente fiable entre sensores/tramos de trafico y aristas del grafo.
- Como se medira exposicion por edge: intensidad media, longitud, capacidad, flujo historico u otra variable.

## Active Plan - M8 Red Viaria Canonica y Contrato de Matching

### 1. Objective
Construir la red viaria canonica minima de trabajo para ROAD-SAFETY y formalizar el contrato tecnico de `accidente -> edge`, dejando preparada la infraestructura espacial para map-matching real y agregacion historica por arista en M9.

### 2. Why this matters for ROAD-SAFETY
Sin una red canonica de nodes/edges no existe una unidad espacial operativa para:
- asignar accidentes a aristas,
- agregar historia por edge,
- separar correctamente bloque contextual, bloque historico_espacial y coste final de routing,
- ni traducir despues el riesgo a pesos de grafo.

### 3. Files involved
Read:
- `PLANS.md`
- `pca_accidentes.R`
- `R/07_historico_espacial_blueprint.R`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/tables/m7_spatial_blueprint.md`

Create:
- `R/08_preparacion_red_canonica.R`
- `outputs/data/m8_road_network_nodes.geojson`
- `outputs/data/m8_road_network_edges.geojson`
- `outputs/data/m8_road_network_nodes.csv`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/tables/m8_network_metadata.csv`
- `outputs/tables/m8_accident_edge_matching_contract.csv`
- `outputs/tables/m8_network_validation_summary.csv`
- `outputs/tables/m8_file_structure_updates.csv`
- `outputs/tables/m8_canonical_network_note.md`

Modify:
- `PLANS.md`
- `pca_accidentes.R`

### 4. Assumptions
- La red canonica se construye desde OpenStreetMap via `osmdata`, no desde el CSV de tramos de trafico.
- El CRS canonico de trabajo es `EPSG:25830` para que distancias y matching se midan en metros.
- Las coordenadas de accidentes se tratan provisionalmente como `EPSG:25830`; M8 debe dejar esa asuncion trazada, no esconderla.
- El bbox de descarga OSM no debe derivarse del extremo bruto de accidentes porque existen outliers; debe usarse un envelope robusto.
- `id_sensor_cercano` sigue siendo un campo auxiliar y queda prohibido como join ingenuo a edge.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar el plan M8 con fuente OSM, CRS, riesgos y entregables.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan M8 escrito y alineado con la separacion baseline / historico_espacial / routing final.
- Validation:
  El plan debe dejar explicito que el tramo de trafico no es la arista final del grafo.

#### Milestone 2
- Purpose:
  Descargar y construir la red viaria canonica minima desde OSM con teselado robusto, geometria valida y reproyeccion consistente.
- Files touched:
  `R/08_preparacion_red_canonica.R`
- Expected output:
  `m8_road_network_nodes.*`, `m8_road_network_edges.*`
- Validation:
  Geometrias validas, CRS explicito, IDs unicos, `from_node_id` / `to_node_id` consistentes y longitudes positivas.

#### Milestone 3
- Purpose:
  Definir el contrato tecnico de matching accidente -> edge.
- Files touched:
  `R/08_preparacion_red_canonica.R`
- Expected output:
  `m8_accident_edge_matching_contract.*`
- Validation:
  Debe documentar campos minimos de accidente, edge y salida de matching, incluyendo distancia punto-edge y metricas de calidad.

#### Milestone 4
- Purpose:
  Documentar metadatos de red, validaciones y la estructura de archivos para M9.
- Files touched:
  `R/08_preparacion_red_canonica.R`
- Expected output:
  `m8_network_metadata.*`, `m8_network_validation_summary.*`, `m8_file_structure_updates.*`, nota tecnica corta.
- Validation:
  Debe quedar claro que tras M8 la red esta lista como backbone espacial, pero aun no existe score final por edge ni routing.

#### Milestone 5
- Purpose:
  Integrar M8 en el runner con cache de artefactos para no reconsultar OSM en cada ejecucion.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M8 ejecutable desde el runner y reusable desde artefactos ya generados.
- Validation:
  El script debe parsear bien y M8 debe poder validarse de forma aislada sin rehacer todo M1-M7.

### 6. Risks
- Riesgo de timeouts en Overpass; mitigacion: descarga por teselas y cache local.
- Riesgo de bbox contaminado por outliers; mitigacion: envelope robusto y buffer controlado.
- Riesgo topologico si cada `way` OSM se toma como un solo edge; mitigacion: segmentacion por vertices para obtener nodes/edges utilizables.
- Riesgo de CRS ambiguo; mitigacion: metadatos y validacion explicita de `EPSG:25830`.
- Riesgo de mezclar red de routing con tramos de trafico; mitigacion: declarar OSM como fuente canonica y el tramo como capa auxiliar.

### 7. Done criteria
- Existen artefactos `m8_road_network_nodes.*` y `m8_road_network_edges.*`.
- Existe metadata de red con fuente, bbox, CRS y estrategia de construccion.
- Existe contrato documentado de matching accidente -> edge.
- Existe resumen de validacion geometrica y topologica minima.
- Queda documentado lo que M9 tendra que hacer: matching real y agregacion historica por edge.

### 8. Open questions
- Si la red OSM canonica se mantendra como fuente final o si mas adelante se fusionara con cartografia municipal.
- Que tolerancia maxima de distancia se aceptara en M9 para un match accidente-edge considerado valido.
- Si el matching real priorizara solo distancia geometrica o una combinacion de distancia, sentido y jerarquia viaria.

## Active Plan - M9 Matching Accidente -> Edge

### 1. Objective
Implementar el matching real `accidente -> edge` sobre la red viaria canonica de M8, con trazabilidad completa, metricas de calidad y salidas auditables para la futura agregacion historica por arista.

### 2. Why this matters for ROAD-SAFETY
Sin matching real no existe puente operativo entre:
- accidentes geolocalizados,
- edges del grafo,
- bloque historico_espacial por arista,
- y edge weighting futuro.

M9 es la primera fase que materializa esa asignacion espacial de manera reproducible y auditable.

### 3. Files involved
Read:
- `pca_accidentes.R`
- `R/08_preparacion_red_canonica.R`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/data/m8_road_network_edges.geojson`
- `outputs/tables/m8_network_metadata.csv`
- `outputs/tables/m8_accident_edge_matching_contract.csv`

Create:
- `R/09_accidente_edge_matching.R`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m9_accident_edge_matches.geojson`
- `outputs/data/m9_unmatched_accidents.csv`
- `outputs/tables/m9_matching_quality_summary.csv`
- `outputs/tables/m9_matching_thresholds.csv`
- `outputs/tables/m9_matching_validation_summary.csv`
- `outputs/tables/m9_matching_note.md`

Modify:
- `PLANS.md`
- `pca_accidentes.R`
- `R/08_preparacion_red_canonica.R`

### 4. Assumptions
- La red canonica de M8 en `EPSG:25830` es la unica base valida para matching.
- Las coordenadas de accidentes en el master se tratan como `EPSG:25830`.
- El radio inicial de busqueda es `30 m`.
- La eleccion del edge se resuelve por distancia punto-segmento minima; empates cercanos se trazan y degradan la calidad.
- `id_sensor_cercano` y `Id. Tram` siguen fuera de la logica de matching.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar M9 con metodo, umbrales y reglas de calidad.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan M9 claro y acotado.
- Validation:
  Debe fijar radio, quality flags, desempate y separacion respecto a score final/routing.

#### Milestone 2
- Purpose:
  Preparar la tabla de accidentes aptos para matching y trazar invalidos / fuera de envelope.
- Files touched:
  `R/09_accidente_edge_matching.R`
- Expected output:
  Accidents matching-ready + unmatched iniciales por invalidez o fuera de envelope.
- Validation:
  Debe cuantificar accidentes validos, fuera de envelope y listos para matching.

#### Milestone 3
- Purpose:
  Ejecutar el matching real contra la geometria de la red canonica y proyectar cada accidente sobre el edge elegido.
- Files touched:
  `R/09_accidente_edge_matching.R`
- Expected output:
  `m9_accident_edge_matches.*`
- Validation:
  `edge_id` existente, distancias metricas en `EPSG:25830`, `projected_point_geometry` valida y `candidate_edges_n` trazado.

#### Milestone 4
- Purpose:
  Generar resumen de calidad, umbrales y validacion auditables.
- Files touched:
  `R/09_accidente_edge_matching.R`
- Expected output:
  `m9_matching_quality_summary.csv`, `m9_matching_thresholds.csv`, `m9_matching_validation_summary.csv`, `m9_matching_note.md`
- Validation:
  Debe incluir porcentaje matched, distribucion de distancias, numero de unmatched, numero por `quality_flag` y reporte de casos fuera de envelope.

#### Milestone 5
- Purpose:
  Integrar M9 en el runner.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M9 ejecutable y reusable desde artefactos M8.
- Validation:
  Parse correcto y ejecucion aislada reproducible.

### 6. Risks
- Riesgo de matching ambiguo en vias paralelas o enlaces complejos.
- Riesgo de baja cobertura si el envelope operativo de M8 deja fuera demasiados accidentes.
- Riesgo de coste computacional alto por volumen de accidentes y edges.
- Riesgo de interpretar un match cercano como correcto cuando hay varios edges casi equidistantes.
- Riesgo de contaminar el matching con joins externos por sensor/tramo; queda explicitamente prohibido.

### 7. Done criteria
- Existen artefactos `m9_*` con matches, unmatched, umbrales, calidad y validacion.
- Todo accidente queda en una de estas categorias: matched, outside_operational_envelope, invalid_coordinates o no_candidate_within_search_radius.
- Cada match guarda distancia punto-edge, proyeccion y quality flag.
- Queda documentado que M9 no construye todavia score final por edge ni routing.

### 8. Open questions
- Si en M10 se incorporara direccion/sentido de circulacion para refinar matching ambiguo.
- Si el umbral operativo de `30 m` debe endurecerse o relajarse tras ver la distribucion real de distancias.

## Active Plan - M10 Agregacion Historica por Edge

### 1. Objective
Construir la primera capa historica por arista a partir de los accidentes ya asignados a `edge_id` en M9, dejando una tabla auditable por edge con:
- conteos historicos raw,
- conteos historicos ponderados por calidad de matching,
- densidad historica por kilometro,
- y un `historical_score_prelim` interpretable, pero todavia separado del coste final de routing.

### 2. Why this matters for ROAD-SAFETY
M10 es el primer puente operativo entre:
- matching geometrico accidente -> edge ya validado,
- bloque historico_espacial a nivel arista,
- y futura combinacion con bloque contextual/dinamico.

Sin esta capa no puede construirse despues un edge weighting serio ni un routing risk-aware.

### 3. Files involved
Read:
- `PLANS.md`
- `pca_accidentes.R`
- `R/09_accidente_edge_matching.R`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/data/m8_road_network_edges.geojson`
- `outputs/tables/m9_matching_validation_summary.csv`

Create:
- `R/10_edge_historical_aggregation.R`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m10_edge_historical_aggregation.geojson`
- `outputs/tables/m10_historical_score_summary.csv`
- `outputs/tables/m10_edge_coverage_summary.csv`
- `outputs/tables/m10_quality_weighting_rule.csv`
- `outputs/tables/m10_top_risk_edges.csv`
- `outputs/tables/m10_historical_score_note.md`
- `outputs/tables/m10_validation_summary.csv`

Modify:
- `PLANS.md`
- `pca_accidentes.R`

### 4. Assumptions
- M10 usa solo accidentes `matched` de M9; `unmatched` y `outside_operational_envelope` quedan fuera de la agregacion historica y se cuantifican aparte.
- Regla conservadora de pesos por `quality_flag`:
  - `high_confidence = 1.00`
  - `medium_confidence = 0.75`
  - `low_confidence = 0.40`
  - `unmatched = 0.00`
- `accidents_per_km` se define sobre el conteo ponderado por calidad:
  - `accident_count_weighted_by_quality / (edge_length_m / 1000)`
- El score preliminar no incorpora todavia exposicion real, severidad ni suavizado espacial.
- `historical_score_prelim` sera una transformacion monotona de `accidents_per_km`, capada en el p95 no nulo y reescalada a `0-100`, para evitar que micro-tramos extremos dominen el ranking preliminar.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar M10 con definiciones separadas de conteo raw, conteo ponderado y score preliminar.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan M10 alineado con M9 y con el futuro bloque historico_espacial.
- Validation:
  Debe dejar claro que `historical_score_prelim` no es todavia peso final de routing.

#### Milestone 2
- Purpose:
  Implementar la agregacion historica por `edge_id` y unirla con la red canonica completa.
- Files touched:
  `R/10_edge_historical_aggregation.R`
- Expected output:
  `m10_edge_historical_aggregation.csv` y `m10_edge_historical_aggregation.geojson`
- Validation:
  Todos los `edge_id` agregados deben existir en la red canonica, no debe haber duplicacion accidental y la suma de `accident_count_raw` debe cuadrar con los `matched` usados.

#### Milestone 3
- Purpose:
  Generar diagnostico de cobertura, regla de pesos y ranking preliminar de aristas historicas.
- Files touched:
  `R/10_edge_historical_aggregation.R`
- Expected output:
  `m10_edge_coverage_summary.csv`, `m10_quality_weighting_rule.csv`, `m10_top_risk_edges.csv`, `m10_historical_score_summary.csv`
- Validation:
  Debe informar cuantas aristas tienen al menos un accidente, distribuciones relevantes y porcentaje de accidentes usados vs excluidos.

#### Milestone 4
- Purpose:
  Documentar la nota tecnica y validaciones de M10.
- Files touched:
  `R/10_edge_historical_aggregation.R`
- Expected output:
  `m10_historical_score_note.md`, `m10_validation_summary.csv`
- Validation:
  Debe dejar explicitas las limitaciones abiertas: sin exposicion, sin severidad, sin suavizado espacial y sin combinacion final con bloque contextual.

#### Milestone 5
- Purpose:
  Integrar M10 en el runner principal.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M10 ejecutable desde el runner y reusable desde artefactos ya generados.
- Validation:
  Parse correcto y ejecucion aislada posible sin relanzar M1-M9.

### 6. Risks
- Riesgo de que tramos muy cortos inflen `accidents_per_km`; mitigacion: dejar `edge_length_m` visible, anadir flags y capar el score preliminar en p95.
- Riesgo de sobreinterpretar la historia cruda como riesgo final; mitigacion: separar conteos, densidad y score transformado en columnas distintas.
- Riesgo de que los `low_confidence` dominen la historia por volumen; mitigacion: descuento fuerte en el conteo ponderado.
- Riesgo de confundir agregacion historica con peso operativo de arista; mitigacion: documentar explicitamente que M10 no implementa routing ni coste final.

### 7. Done criteria
- Existen todos los artefactos `m10_*`.
- La agregacion por edge es unica y auditable.
- La suma de accidentes raw agregados coincide con los `matched` usados.
- `edge_length_m > 0` para la red usada.
- `historical_score_prelim` queda documentado como score preliminar, no como peso final de routing.

### 8. Open questions
- Como incorporar mas adelante exposicion real por edge o por clase viaria.
- Si convendra suavizado espacial entre aristas adyacentes antes de routing.
- Como incorporar severidad historica y combinacion con bloque contextual/dinamico en fases posteriores.

## Active Plan - M11 Crosswalk Trafico/Exposicion -> Edge

### 1. Objective
Construir el primer puente operativo entre:
- capas de trafico / sensores disponibles,
- `edge_id` de la red canonica,
- y la capa historica por arista de M10,

dejando una base de exposicion preliminar por edge y un `historical_exposure_adjusted_score_prelim` todavia separado del coste final de routing.

### 2. Why this matters for ROAD-SAFETY
M10 deja historia por edge, pero todavia sin una base de exposicion.  
Sin M11 no puede empezarse a distinguir entre:
- edges con mas accidentes porque concentran mas exposicion de trafico,
- y edges con senal historica alta incluso una vez descontada una proxy de exposicion.

M11 tambien deja preparado el puente metodologico hacia la futura capa dinamica/contextual.

### 3. Files involved
Read:
- `PLANS.md`
- `pca_accidentes.R`
- `R/08_preparacion_red_canonica.R`
- `R/10_edge_historical_aggregation.R`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/data/m8_road_network_edges.geojson`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/tables/m10_quality_weighting_rule.csv`
- `bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`

Create:
- `R/11_edge_exposure_crosswalk.R`
- `outputs/tables/m11_edge_traffic_crosswalk.csv`
- `outputs/tables/m11_edge_sensor_crosswalk.csv`
- `outputs/tables/m11_edge_exposure_baseline.csv`
- `outputs/tables/m11_historical_exposure_adjusted.csv`
- `outputs/tables/m11_crosswalk_quality_summary.csv`
- `outputs/tables/m11_exposure_note.md`
- `outputs/tables/m11_validation_summary.csv`

Modify:
- `PLANS.md`
- `pca_accidentes.R`

### 4. Assumptions
- El crosswalk `tramo -> edge` debe ser geometrico y auditable; queda prohibido hacer join directo por `Id. Tram`.
- El crosswalk `sensor -> edge` no tiene capa puntual independiente en el repo, asi que se construye de forma `accident-backed` usando M9 + `id_sensor_cercano`; queda prohibido tratar `id_sensor_cercano` como `edge_id`.
- Primera base de exposicion:
  - fuente preferente: indice proxy derivado de `intensidad` y `ocupacion` asociados a sensores observados en accidentes matcheados,
  - no unidad fisica de exposicion real,
  - si no hay proxy numerica suficiente, el edge queda como `no_proxy`.
- `historical_exposure_adjusted_score_prelim` se construye sobre `accidents_per_km` de M10 dividido por una proxy de exposicion suavizada:
  - `historical_exposure_adjusted_density = accidents_per_km / (0.25 + exposure_proxy_value)`
  - despues se reescala a `0-100` capando en el p95 no nulo.
- Si la capa lineal de trafico no es espacialmente interoperable con la red canonica actual, M11 no la forzara: dejara la cobertura a `0` y documentara el bloqueo.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar M11 y fijar la separacion entre crosswalk geometrico, exposure baseline y score historico ajustado por exposicion.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan M11 alineado con M10 y limpio metodologicamente.
- Validation:
  Debe dejar claro que ni la exposicion proxy ni el score ajustado son todavia coste final de routing.

#### Milestone 2
- Purpose:
  Implementar el crosswalk geometrico `tramo -> edge` y cuantificar su cobertura real.
- Files touched:
  `R/11_edge_exposure_crosswalk.R`
- Expected output:
  `m11_edge_traffic_crosswalk.csv`
- Validation:
  Debe usar geometria real, no joins ingenuos, y cuantificar si la capa es util o no para la red actual.

#### Milestone 3
- Purpose:
  Implementar el crosswalk `sensor -> edge` respaldado por accidentes ya matcheados.
- Files touched:
  `R/11_edge_exposure_crosswalk.R`
- Expected output:
  `m11_edge_sensor_crosswalk.csv`
- Validation:
  Debe trazar evidencia por `edge_id` / `sensor_id`, pesos, dominancia y calidad del enlace.

#### Milestone 4
- Purpose:
  Construir la tabla baseline de exposicion por edge y el score historico ajustado por exposicion.
- Files touched:
  `R/11_edge_exposure_crosswalk.R`
- Expected output:
  `m11_edge_exposure_baseline.csv`, `m11_historical_exposure_adjusted.csv`
- Validation:
  Debe separar raw historical counts, weighted historical counts, exposure proxy y score ajustado preliminar.

#### Milestone 5
- Purpose:
  Documentar cobertura, limitaciones y validaciones finales.
- Files touched:
  `R/11_edge_exposure_crosswalk.R`
- Expected output:
  `m11_crosswalk_quality_summary.csv`, `m11_exposure_note.md`, `m11_validation_summary.csv`
- Validation:
  Debe quedar explicito que la exposicion sigue siendo proxy y que no existe aun coste final de routing.

#### Milestone 6
- Purpose:
  Integrar M11 en el runner.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M11 ejecutable tras M10.
- Validation:
  Parse correcto y ejecucion aislada posible usando artefactos M8-M10.

### 6. Risks
- Riesgo de mismatch espacial entre la capa lineal de trafico disponible y la red canonica actual.
- Riesgo de interpretar `id_sensor_cercano` como identificador espacial directo; queda prohibido y se sustituye por un crosswalk respaldado por M9.
- Riesgo de sobreinterpretar una proxy de exposicion derivada de `intensidad` / `ocupacion` observadas en accidentes.
- Riesgo de baja cobertura de exposicion fuera de edges con accidentes ya matcheados.

### 7. Done criteria
- Existen todos los artefactos `m11_*`.
- El crosswalk geometrico no usa joins directos ingenuos.
- La cobertura del crosswalk queda cuantificada, incluso si es baja o nula.
- `exposure_proxy_value` queda documentado y trazable.
- `historical_exposure_adjusted_score_prelim` queda marcado como preliminar y no como peso final de routing.
- Queda explicito que edges tienen proxy fiable, proxy debil o ausencia de proxy.

### 8. Open questions
- Como incorporar una fuente externa de intensidad/exposicion verdaderamente independiente del dataset de accidentes.
- Si convendra una capa de sensores con geometria propia para sustituir el crosswalk `accident-backed`.
- Como combinar despues esta exposicion baseline con capa dinamica/contextual sin doble conteo.

## Active Plan - M12 Capa Dinamica/Contextual por Edge

### 1. Objective
Construir la primera capa dinamica/contextual por edge, separada del historico y de la exposicion, usando solo variables ya auditadas y utiles hoy:
- `intensidad`
- `ocupacion`
- `hour_sin`
- `hour_cos`
- `is_weekend`

dejando fuera por ahora:
- `vmed`
- `es_festivo`
- meteorologia sin integracion operativa

y produciendo una base contextual por observacion agregada que pueda alimentarse con nuevas observaciones en fases posteriores.

### 2. Why this matters for ROAD-SAFETY
M10 y M11 dejan:
- historia por edge,
- ajuste baseline por exposicion,

pero todavia falta una capa separada que represente el estado contextual/dinamico del edge en una ventana temporal.  
Sin M12 no existe un puente limpio hacia una futura combinacion `historico + contexto` ni hacia una eventual capa de routing dependiente del momento.

### 3. Files involved
Read:
- `PLANS.md`
- `pca_accidentes.R`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/tables/m11_validation_summary.csv`
- `outputs/tables/m6_index_blueprint.csv`
- `outputs/tables/m6_final_variable_status.csv`

Create:
- `R/12_edge_dynamic_context.R`
- `outputs/data/m12_edge_context_dynamic_base.csv`
- `outputs/tables/m12_dynamic_context_summary.csv`
- `outputs/tables/m12_context_variable_registry.csv`
- `outputs/tables/m12_dynamic_signal_note.md`
- `outputs/tables/m12_validation_summary.csv`

Modify:
- `PLANS.md`
- `pca_accidentes.R`

### 4. Assumptions
- Unidad observacional de M12:
  - `edge_id + temporal_bin_4h + is_weekend`
- Justificacion:
  - una malla horaria completa por edge seria demasiado dispersa con el soporte actual,
  - bins de 4 horas conservan interpretabilidad temporal,
  - permiten calcular `hour_sin` / `hour_cos` sobre un centro de bin estable,
  - y dejan una tabla preparada para futuras observaciones nuevas.
- `dynamic_context_signal_prelim` se implementa ya, pero solo para el bloque usable hoy:
  - bloque `trafico_contexto = intensidad + ocupacion`
- `hour_sin`, `hour_cos` e `is_weekend` entran en la base contextual como descriptores ya utilizables, pero no se convierten todavia en senal numerica de riesgo por si solos.
- `vmed` queda fuera por variable under review.
- `es_festivo` queda fuera del baseline dinamico por desbalance y porque su papel contextual sigue siendo mas de modulador que de eje principal.
- `estado_meteorologico` queda fuera hasta que exista una integracion operativa y comparable.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar M12 con la unidad observacional y la separacion historico / exposicion / contexto / peso final futuro.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan M12 metodologicamente limpio.
- Validation:
  Debe dejar claro que M12 no calcula todavia coste final de routing.

#### Milestone 2
- Purpose:
  Preparar la base observacional contextual desde accidentes matched, con bins temporales y variables contextuales auditadas.
- Files touched:
  `R/12_edge_dynamic_context.R`
- Expected output:
  Base observacional agregada por `edge_id + temporal_bin_4h + is_weekend`
- Validation:
  Debe trazar cuantas observaciones alimentan cada row y que variables faltan.

#### Milestone 3
- Purpose:
  Generar la registry de variables y dejar explicito que entra ya y que queda fuera.
- Files touched:
  `R/12_edge_dynamic_context.R`
- Expected output:
  `m12_context_variable_registry.csv`
- Validation:
  Debe documentar uso real, no aspiracional.

#### Milestone 4
- Purpose:
  Implementar un `dynamic_context_signal_prelim` simple, auditable y no falso.
- Files touched:
  `R/12_edge_dynamic_context.R`
- Expected output:
  `m12_edge_context_dynamic_base.csv`
- Validation:
  Debe basarse solo en `intensidad` / `ocupacion` y dejar el bloque temporal como descriptor listo para modelado posterior.

#### Milestone 5
- Purpose:
  Documentar resumen, validacion y limitaciones de la capa dinamica/contextual.
- Files touched:
  `R/12_edge_dynamic_context.R`
- Expected output:
  `m12_dynamic_context_summary.csv`, `m12_dynamic_signal_note.md`, `m12_validation_summary.csv`
- Validation:
  Debe quedar explicito que el score dinamico preliminar no es peso final de routing y que faltan meteorologia, severidad, calibracion y combinacion definitiva.

#### Milestone 6
- Purpose:
  Integrar M12 en el runner.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M12 ejecutable tras M11.
- Validation:
  Parse correcto y ejecucion aislada posible sobre artefactos M8-M11.

### 6. Risks
- Riesgo de confundir contexto accident-backed con una capa dinamica operativa en tiempo real.
- Riesgo de sobreinterpretar `hour_sin` / `hour_cos` / `is_weekend` como riesgo numerico sin modelo supervisado ni feed exogeno.
- Riesgo de forzar `vmed` dentro del signal pese a su revision metodologica previa.
- Riesgo de mezclar contexto con historico en una sola columna y perder auditabilidad.

### 7. Done criteria
- Existen todos los artefactos `m12_*`.
- La unidad observacional de M12 queda explicita.
- Las variables contextuales usadas y excluidas quedan trazadas.
- `dynamic_context_signal_prelim` existe solo como baseline simple y auditable.
- `historical_exposure_adjusted_score_prelim` sigue separado y no es reemplazado por M12.
- Queda explicito que `future_combined_edge_risk` es solo placeholder conceptual.

### 8. Open questions
- Que feed exogeno real alimentara en el futuro la capa dinamica/contextual fuera de accidentes observados.
- Como incorporar meteorologia, severidad y calibracion supervisada.
- Como combinar despues `historical_exposure_adjusted_score_prelim` y `dynamic_context_signal_prelim` sin doble conteo ni leakage.

## Active Plan - M13 Riesgo Combinado Preliminar por Edge

### 1. Objective
Construir la primera capa de riesgo combinado por:
- `edge_id`
- `temporal_bin_4h`
- `is_weekend`

manteniendo separadas y trazables:
- `historical_component`
- `exposure_adjusted_historical_component`
- `dynamic_component`
- `combined_edge_risk_prelim`

sin convertir todavia ese resultado en coste final de routing.

### 2. Why this matters for ROAD-SAFETY
M10-M12 ya dejan:
- una capa historica por edge,
- un ajuste baseline por exposicion,
- una capa dinamica/contextual por edge y bin temporal.

M13 es el primer puente operativo entre esas piezas.  
Sin esta fase no existe una base combinada auditable para estudiar como cambiarian los rankings de edge cuando se mezcla historia estructural y contexto actual, aunque todavia no haya routing.

### 3. Files involved
Read:
- `PLANS.md`
- `pca_accidentes.R`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`
- `outputs/tables/m10_validation_summary.csv`
- `outputs/tables/m11_validation_summary.csv`
- `outputs/tables/m12_validation_summary.csv`

Create:
- `R/13_edge_combined_risk_prelim.R`
- `outputs/data/m13_edge_combined_risk_prelim.csv`
- `outputs/tables/m13_combined_risk_summary.csv`
- `outputs/tables/m13_weighting_rule.csv`
- `outputs/tables/m13_sensitivity_summary.csv`
- `outputs/tables/m13_top_changed_edges.csv`
- `outputs/tables/m13_combined_risk_note.md`
- `outputs/tables/m13_validation_summary.csv`

Modify:
- `PLANS.md`
- `pca_accidentes.R`

### 4. Assumptions
- La tabla operativa de M13 reutiliza la unidad observacional de M12:
  - `edge_id + temporal_bin_4h + is_weekend`
- La combinacion baseline usa una media ponderada simple en escala `0-100`:
  - `historical_weight = 2/3`
  - `dynamic_weight = 1/3`
- Justificacion:
  - el bloque historico ajustado por exposicion es hoy mas estable porque agrega senal multi-anual,
  - el bloque dinamico/contextual ya es util, pero sigue siendo mas parcial y accident-backed,
  - una regla `2:1` es facil de auditar y no deriva pesos de PCA.
- Cuando exista `historical_exposure_adjusted_score_prelim`, M13 lo usa como historico principal.
- Si ese score ajustado falta, M13 hace fallback explicito a `historical_score_prelim`.
- Si el componente dinamico falta, M13 no inventa contexto y usa solo el historico disponible.
- Sensibilidades minimas:
  - `historical_heavy = 4/5 historico + 1/5 dinamico`
  - `dynamic_heavy = 2/5 historico + 3/5 dinamico`

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar la regla de combinacion y sus escenarios de sensibilidad.
- Files touched:
  `PLANS.md`
- Expected output:
  Regla baseline y sensibilidades documentadas.
- Validation:
  Debe quedar explicito que el score combinado no es peso final de routing.

#### Milestone 2
- Purpose:
  Construir la tabla combinada por edge/bin reutilizando M10-M12 sin pisar componentes.
- Files touched:
  `R/13_edge_combined_risk_prelim.R`
- Expected output:
  `m13_edge_combined_risk_prelim.csv`
- Validation:
  Debe incluir separados `historical_component`, `exposure_adjusted_historical_component`, `dynamic_component` y `combined_edge_risk_prelim`.

#### Milestone 3
- Purpose:
  Documentar la regla de weighting y el fallback de componentes faltantes.
- Files touched:
  `R/13_edge_combined_risk_prelim.R`
- Expected output:
  `m13_weighting_rule.csv`
- Validation:
  Debe explicar baseline, historical-heavy, dynamic-heavy y el manejo de `NA`.

#### Milestone 4
- Purpose:
  Generar diagnostico de sensibilidad y cambios de ranking.
- Files touched:
  `R/13_edge_combined_risk_prelim.R`
- Expected output:
  `m13_sensitivity_summary.csv`, `m13_top_changed_edges.csv`
- Validation:
  Debe mostrar que edges cambian mas cuando se pesa mas el historico o mas el dinamico.

#### Milestone 5
- Purpose:
  Documentar limitaciones y validar que M13 sigue siendo una capa preliminar.
- Files touched:
  `R/13_edge_combined_risk_prelim.R`
- Expected output:
  `m13_combined_risk_summary.csv`, `m13_combined_risk_note.md`, `m13_validation_summary.csv`
- Validation:
  Debe quedar explicito que no hay severidad, meteorologia operativa completa, calibracion final ni peso final de routing.

#### Milestone 6
- Purpose:
  Integrar M13 en el runner.
- Files touched:
  `pca_accidentes.R`
- Expected output:
  M13 ejecutable tras M12.
- Validation:
  Parse correcto y ejecucion aislada posible sobre artefactos M8-M12.

### 6. Risks
- Riesgo de vender como calibrada una combinacion que todavia es solo una regla operativa preliminar.
- Riesgo de mezclar `historical_score_prelim` y `historical_exposure_adjusted_score_prelim` sin dejar claro cual entra realmente en la combinacion.
- Riesgo de sobreinterpretar cambios de ranking cuando el componente dinamico falta o es mas debil.
- Riesgo de olvidar que la capa combinada sigue sin severidad, meteorologia operativa completa ni validacion supervisada.

### 7. Done criteria
- Existen todos los artefactos `m13_*`.
- `edge_id` en salida existe en la red canonica.
- La combinacion no pisa ni reemplaza los componentes originales.
- `combined_edge_risk_prelim` queda trazado por componentes.
- La salida deja claro que parte viene del historico y cual del contexto.
- `combined_edge_risk_prelim_is_final_routing_weight = FALSE`.

### 8. Open questions
- Como calibrar despues la mezcla historico/contexto contra objetivos operativos reales.
- Como incorporar severidad y meteorologia sin romper la auditabilidad de la capa combinada.
- Como traducir mas adelante esta capa combinada preliminar a un coste final de routing sin doble conteo.

## Active Plan - Python Modeling Phase / Training Table

### 1. Objective
Arrancar la fase de modelado predictivo en Python sin rehacer M1-M12, construyendo primero una training table auditable con target real observado y ceros defendibles.

### 2. Working assumptions
- La unidad preferida del proyecto es `edge_id + temporal_bin_4h + is_weekend`.
- Para poder tener ceros observados y split temporal defendible, la tabla de entrenamiento se ampliara minimamente a:
  - `edge_id + analysis_year + temporal_bin_4h + is_weekend`
- Justificacion:
  - sin una dimension temporal de panel no existe validacion temporal real;
  - los ceros agregados sobre todo el periodo serian demasiado toscos;
  - `analysis_year` es la extension minima que preserva la logica de M12 y evita pasar demasiado pronto a granularidades mas inestables.
- El target inicial sera `accident_count`.
- `accident_rate` queda aparcado hasta que exista una exposicion mas defendible a nivel observacion.

### 3. Inputs that actually support modeling
Read:
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/data/m8_road_network_edges.geojson` solo como referencia espacial futura, no para la training table tabular inicial
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`

Create:
- `modeling/`
- `modeling/config.py`
- `modeling/build_training_table.py`
- `modeling/train_baseline.py`
- `modeling/evaluate.py`
- `modeling/score.py`
- `outputs/modeling/data/`
- `outputs/modeling/tables/`
- `outputs/modeling/data/training_table_edge_year_bin_weekend.parquet`
- `outputs/modeling/tables/training_table_summary.csv`
- `outputs/modeling/tables/training_feature_registry.csv`

Modify:
- `PLANS.md`

### 4. Target and feature logic
- Target principal:
  - `accident_count`
- No se usara ningun score heuristico tipo M13 como target.
- Features historicas/base candidatas:
  - `edge_length_m`
  - `historical_score_prelim_full_period_reference`
  - `historical_exposure_adjusted_score_prelim_full_period_reference`
  - features lag-safe derivadas del propio historial por edge/panel, por ejemplo:
    - `edge_accident_count_prior_total`
    - `edge_bin_accident_count_prior`
    - `edge_years_observed_prior`
- Features contextuales/dinamicas candidatas:
  - `hour_sin`
  - `hour_cos`
  - `is_weekend`
  - columnas de M12 como referencia:
    - `intensidad_context_full_period_reference`
    - `ocupacion_context_full_period_reference`
    - `dynamic_context_signal_prelim_full_period_reference`
- Variables que quedan fuera del baseline model-safe inicial:
  - `vmed` por ruido ya conocido
  - `es_festivo` por desbalance y porque no esta integrada aqui como bloque estable
  - `meteorologia` por falta de integracion operativa usable
- Importante:
  - Las columnas full-period derivadas de M11/M12 se guardaran como `reference_only` o `leakage_risk_for_temporal_split`, no como features baseline seguras por defecto.

### 5. Milestones

#### Milestone 1
- Purpose:
  Diagnostico inicial y definicion de unidad/target/features.
- Expected output:
  Plan metodologico de modelado.
- Validation:
  Debe quedar explicito por que `analysis_year` se anade a la unidad preferida.

#### Milestone 2
- Purpose:
  Crear estructura `modeling/` en Python sin mezclar todo en un script gigante.
- Expected output:
  Modulos separados para build/train/evaluate/score.
- Validation:
  Rutas reproducibles y estructura clara.

#### Milestone 3
- Purpose:
  Construir training table inicial con target real y ceros.
- Expected output:
  `training_table_edge_year_bin_weekend.parquet`
- Validation:
  Debe incluir `accident_count = 0` para observaciones del panel sin accidente observado.

#### Milestone 4
- Purpose:
  Documentar que columnas son model-safe y cuales son solo referencia/base comparativa.
- Expected output:
  `training_feature_registry.csv`
- Validation:
  Debe separar `model_safe`, `reference_only` y `excluded_for_now`.

#### Milestone 5
- Purpose:
  Validar la training table antes de entrenar ningun baseline.
- Expected output:
  `training_table_summary.csv`
- Validation:
  Debe informar tamaño, ceros, porcentaje de ceros, cobertura de joins y lag features.

### 6. Risks
- Riesgo de leakage si se usan directamente como predictors columnas full-period derivadas de M11/M12.
- Riesgo de confundir observaciones accident-backed con un feed contextual real.
- Riesgo de fabricar ceros fuera de un soporte temporal defendible.
- Riesgo de entrenar solo con positivos si no se construye bien el panel.

### 7. Done criteria for this first implementation
- Existe la carpeta `modeling/` con estructura minima clara.
- Existe una training table auditable en Python con target real `accident_count`.
- La training table incluye ceros.
- Las claves de join quedan documentadas y consistentes.
- Queda explicito que no hay aun modelo entrenado ni routing.

### 8. Open questions
- Como obtener contexto dinamico realmente exogeno y no accident-backed.
- Como convertir las columnas de M11/M12 en predictors temporales sin leakage.
- Cuando merece la pena pasar de Poisson a Negative Binomial segun la dispersion observada.

## Active Plan - Python Modeling Phase / Zero-Only Controls and First Poisson Baseline

### 1. Objective
Corregir el sesgo de la training table actual hacia edges con historial positivo, incorporar una muestra auditable de edges nunca accidentados con `accident_count = 0`, y entrenar el primer baseline Poisson usando solo features `model_safe`.

### 2. Why this matters for ROAD-SAFETY
ROAD-SAFETY no acabara puntuando solo edges con historial de accidente.  
Si el primer baseline se entrena solo sobre edges que alguna vez tuvieron accidentes matched, el modelo aprende un universo sesgado y pierde validez para el scoring futuro de red completa.

### 3. Files involved
Read:
- `outputs/modeling/data/training_table_edge_year_bin_weekend.parquet`
- `outputs/modeling/tables/training_table_summary.csv`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/m10_edge_historical_aggregation.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`

Create:
- `modeling/build_training_table_with_controls.py`
- `outputs/modeling/training_table_with_controls.parquet`
- `outputs/modeling/training_table_with_controls_summary.csv`
- `outputs/modeling/poisson_baseline_metrics.csv`
- `outputs/modeling/poisson_baseline_coefficients.csv`
- `outputs/modeling/poisson_baseline_note.md`
- `outputs/modeling/poisson_baseline_predictions.csv`

Modify:
- `PLANS.md`
- `modeling/config.py`
- `modeling/train_baseline.py`
- `modeling/build_training_table.py`

### 4. Assumptions
- La training table actual representa `training_table_current` y contiene solo edges con historial matched.
- La correccion no expandira ciegamente toda la red; se usara una muestra estratificada de zero-only controls.
- Estratificacion de controls:
  - `road_class`
  - `edge_length_bin`
- Regla de muestreo:
  - hasta `1:1` por estrato respecto a los edges con historial positivo,
  - capada por el tamano real del pool de edges sin accidentes.
- Los zero-only controls heredan una plantilla de soporte temporal `first_year:last_year` muestreada desde edges positivos del mismo estrato.
- El primer baseline usa solo features `model_safe`; no usa `reference_only`.
- Split temporal baseline:
  - `train = 2016-2022`
  - `validation = 2023`
  - `test = 2024`

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar el sesgo de cobertura de la training table actual y fijar el esquema de zero-only controls.
- Files touched:
  `PLANS.md`
- Expected output:
  Plan metodologico limpio y acotado.
- Validation:
  Debe quedar explicito si la tabla actual cubre solo edges con historial positivo.

#### Milestone 2
- Purpose:
  Construir `training_table_with_zero_only_controls` sin rehacer M1-M12.
- Files touched:
  `modeling/build_training_table_with_controls.py`, `modeling/config.py`, `modeling/build_training_table.py`
- Expected output:
  `training_table_with_controls.parquet`, `training_table_with_controls_summary.csv`
- Validation:
  Debe cuantificar filas totales, positivos, ceros, edges unicos y proporcion de edges con y sin historial.

#### Milestone 3
- Purpose:
  Entrenar el primer baseline Poisson con features `model_safe`.
- Files touched:
  `modeling/train_baseline.py`, `modeling/config.py`
- Expected output:
  Artefactos `poisson_baseline_*`
- Validation:
  Debe informar distribucion del target por split, dispersion, mean Poisson deviance, MAE, RMSE y calibracion basica.

### 6. Risks
- Riesgo de inflar demasiado la tabla si se expanden demasiados zero-only controls.
- Riesgo de fabricar soporte temporal irreal para edges nunca accidentados.
- Riesgo de leakage si se cuelan features `reference_only` en el baseline.
- Riesgo de sobre-dispersion fuerte que deje corto el Poisson y obligue a pasar despues a Negative Binomial.

### 7. Done criteria
- Existe una tabla `training_table_with_controls` auditable y separada de `training_table_current`.
- La cobertura de edges con y sin historial queda cuantificada.
- El primer baseline Poisson usa solo features `model_safe`.
- Existen metricas y coeficientes reproducibles.
- Queda explicito que el baseline no es peso final de routing ni modelo final del sistema.

### 8. Open questions
- Si mas adelante se ampliara el pool de zero-only controls o se pasara a una cobertura mas cercana a red completa.
- Si la dispersion del Poisson justificara pasar en la siguiente fase a Negative Binomial.

## Active Plan - Python Modeling Phase / Baseline B Negative Binomial

### 1. Objective
Entrenar y evaluar un baseline Negative Binomial sobre la misma `training_table_with_controls.parquet`, con el mismo split temporal y el mismo bloque de features `model_safe` del baseline Poisson A, para compararlos limpiamente.

### 2. Why this matters for ROAD-SAFETY
Antes de pasar a modelos mas flexibles o a features contextuales con mas riesgo de leakage, hace falta comprobar si la sobredispersion observada fuera de train justifica un count model mas flexible que Poisson.

### 3. Files involved
Read:
- `outputs/modeling/training_table_with_controls.parquet`
- `outputs/modeling/poisson_baseline_metrics.csv`
- `outputs/modeling/poisson_baseline_predictions.csv`
- `outputs/modeling/poisson_baseline_coefficients.csv`
- `outputs/modeling/training_table_with_controls_summary.csv`
- `modeling/train_baseline.py`
- `modeling/config.py`

Create:
- `modeling/train_negative_binomial.py`
- `outputs/modeling/negative_binomial_baseline_metrics.csv`
- `outputs/modeling/negative_binomial_baseline_coefficients.csv`
- `outputs/modeling/negative_binomial_baseline_predictions.csv`
- `outputs/modeling/negative_binomial_baseline_note.md`
- `outputs/modeling/poisson_vs_nb_comparison.csv`
- `outputs/modeling/poisson_vs_nb_note.md`

Modify:
- `PLANS.md`
- `modeling/config.py`

### 4. Assumptions
- Target fijo:
  - `accident_count`
- Split fijo:
  - `train = 2016-2022`
  - `validation = 2023`
  - `test = 2024`
- Features fijas:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
- No se usan `reference_only`.
- Negative Binomial se intentara con `statsmodels` del entorno actual.
- Si el ajuste MLE completo fallara por limitacion tecnica real, la unica alternativa aceptable en esta fase seria una variante `statsmodels` con alpha fijado y documentado. No se cambiara target ni split.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar la viabilidad real de Negative Binomial con las librerias disponibles.
- Files touched:
  `PLANS.md`
- Expected output:
  Decision tecnica de libreria/metodo.
- Validation:
  Debe quedar claro que el baseline B usa el mismo split y las mismas features que A.

#### Milestone 2
- Purpose:
  Entrenar el baseline Negative Binomial B.
- Files touched:
  `modeling/config.py`, `modeling/train_negative_binomial.py`
- Expected output:
  Artefactos `negative_binomial_baseline_*`
- Validation:
  Debe generar predicciones, metricas y coeficientes sin tocar la training table.

#### Milestone 3
- Purpose:
  Comparar Poisson A vs Negative Binomial B.
- Files touched:
  `modeling/train_negative_binomial.py`
- Expected output:
  `poisson_vs_nb_comparison.csv`, `poisson_vs_nb_note.md`
- Validation:
  Debe comparar validation y test en deviance, MAE, RMSE, dispersion, calibracion y comportamiento en ceros/positivos.

### 6. Risks
- Riesgo de que el ajuste NB completo sea mas pesado computacionalmente que Poisson.
- Riesgo de que la mejora exista pero sea marginal y no justifique aumentar complejidad.
- Riesgo de sobredispersion fuera de train aunque el train quede razonablemente ajustado.

### 7. Done criteria
- Negative Binomial entrenado sobre la misma tabla, split y features.
- Existen todos los artefactos `negative_binomial_baseline_*` y `poisson_vs_nb_*`.
- La comparacion deja claro si la mejora NB es material o marginal.
- Queda explicito que ningun baseline es todavia peso final de routing.

### 8. Open questions
- Si tras esta comparacion el siguiente paso debe ser NB estable o features contextuales leak-safe.
- Si los ceros estructurales justifican mas adelante hurdle o zero-inflated.

## Active Plan - Python Modeling Phase / Leak-Safe Contextual Features

### 1. Objective
Construir una nueva version de la training table con features contextuales/temporales leak-safe calculadas solo con informacion disponible antes de cada observacion, sin cambiar ni el target `accident_count` ni el split temporal ya fijado.

### 2. Why this matters for ROAD-SAFETY
La comparacion Poisson vs Negative Binomial ya esta cerrada y muestra que el siguiente cuello de botella no es tanto la familia del modelo como la calidad de las features.  
Antes de pasar a otra iteracion de baseline hace falta un bloque nuevo de predictores historico-contextuales que no introduzca leakage y que siga siendo auditable.

### 3. Files involved
Read:
- `outputs/modeling/training_table_with_controls.parquet`
- `outputs/modeling/tables/training_feature_registry.csv`
- `outputs/modeling/poisson_baseline_metrics.csv`
- `outputs/modeling/negative_binomial_baseline_metrics.csv`
- `outputs/tables/m11_exposure_note.md`
- `outputs/tables/m12_dynamic_signal_note.md`

Create:
- `modeling/build_lag_safe_features.py`
- `outputs/modeling/training_table_with_lag_safe_features.parquet`
- `outputs/modeling/lag_safe_feature_registry.csv`
- `outputs/modeling/lag_safe_feature_summary.csv`
- `outputs/modeling/lag_safe_feature_note.md`

Modify:
- `PLANS.md`
- `modeling/config.py`

### 4. Assumptions
- Target fijo:
  - `accident_count`
- Split fijo:
  - `train = 2016-2022`
  - `validation = 2023`
  - `test = 2024`
- La unidad observacional se mantiene:
  - `edge_id + analysis_year + temporal_bin_4h + is_weekend`
- No se usaran como predictores directos columnas full-period accident-backed de M11/M12.
- Las nuevas features se derivaran solo de historia estrictamente anterior a `analysis_year`.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar columnas actuales y separar `safe_now`, `unsafe_due_to_leakage` y `potentially_rebuildable_as_lagged`.
- Files touched:
  `PLANS.md`
- Expected output:
  Criterio metodologico cerrado para el nuevo bloque.
- Validation:
  Debe quedar explicito que M11/M12 full-period no entran directos.

#### Milestone 2
- Purpose:
  Construir nuevas lag-safe contextual features desde la tabla actual.
- Files touched:
  `modeling/build_lag_safe_features.py`, `modeling/config.py`
- Expected output:
  `training_table_with_lag_safe_features.parquet`
- Validation:
  Cada feature nueva debe depender solo de historia previa.

#### Milestone 3
- Purpose:
  Documentar registry, cobertura, missingness y limitaciones.
- Files touched:
  `modeling/build_lag_safe_features.py`
- Expected output:
  `lag_safe_feature_registry.csv`, `lag_safe_feature_summary.csv`, `lag_safe_feature_note.md`
- Validation:
  Debe separar `original_model_safe`, `new_lag_safe_contextual_features` y `reference_only`.

### 6. Risks
- Riesgo de introducir leakage si se reutilizan directamente agregados full-period accident-backed.
- Riesgo de confundir actividad previa con contexto exogeno real.
- Riesgo de crear features de tendencia demasiado inestables o con mucha falta de soporte.

### 7. Done criteria
- Existe una nueva tabla `training_table_with_lag_safe_features`.
- Las nuevas features quedan documentadas, con missingness y cobertura.
- Queda claro que target y split no cambian.
- No se entrena todavia el siguiente baseline en esta fase.

### 8. Open questions
- Que subset exacto de estas nuevas features convendra llevar al siguiente baseline.
- Si merece la pena reconstruir mas adelante proxies de M11/M12 de forma rolling y leak-safe.

## Active Plan - Python Modeling Phase / A2-B2 Lag-Safe Baseline Comparison

### 1. Objective
Entrenar y comparar:
- `Poisson A2`
- `Negative Binomial B2`

sobre `training_table_with_lag_safe_features.parquet`, manteniendo:
- mismo target `accident_count`
- mismo split temporal
- y un bloque conservador de features compuesto por `original_model_safe` + un subconjunto limpio de `new_lag_safe_contextual_features`.

### 2. Why this matters for ROAD-SAFETY
La comparacion A/B ya esta cerrada.  
Ahora hace falta comprobar si las nuevas lag-safe contextual features mejoran de verdad el baseline, antes de abrir la puerta a integracion contextual mas rica, modelos mas complejos o decisiones de routing.

### 3. Files involved
Read:
- `outputs/modeling/training_table_with_lag_safe_features.parquet`
- `outputs/modeling/lag_safe_feature_registry.csv`
- `outputs/modeling/lag_safe_feature_summary.csv`
- `outputs/modeling/poisson_baseline_metrics.csv`
- `outputs/modeling/negative_binomial_baseline_metrics.csv`
- `outputs/modeling/poisson_vs_nb_comparison.csv`
- `modeling/train_baseline.py`
- `modeling/train_negative_binomial.py`

Create:
- `modeling/train_lag_safe_baselines.py`
- `outputs/modeling/poisson_a2_metrics.csv`
- `outputs/modeling/poisson_a2_coefficients.csv`
- `outputs/modeling/poisson_a2_predictions.csv`
- `outputs/modeling/negative_binomial_b2_metrics.csv`
- `outputs/modeling/negative_binomial_b2_coefficients.csv`
- `outputs/modeling/negative_binomial_b2_predictions.csv`
- `outputs/modeling/a2_b2_comparison.csv`
- `outputs/modeling/a2_b2_note.md`
- `outputs/modeling/baseline_ab_vs_a2b2_comparison.csv`

Modify:
- `PLANS.md`
- `modeling/config.py`

### 4. Assumptions
- Target fijo:
  - `accident_count`
- Split fijo:
  - `train = 2016-2022`
  - `validation = 2023`
  - `test = 2024`
- Features originales mantenidas:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
- Subconjunto nuevo conservador:
  - `log1p_edge_accident_count_prior_1y`
  - `log1p_edge_bin_accident_count_prior_1y`
  - `log1p_edge_accident_count_prior_recent_3y`
  - `log1p_edge_bin_accident_count_prior_recent_3y`
- Se dejan fuera por prudencia:
  - `edge_years_since_last_accident`
  - `edge_bin_years_since_last_accident`
  - `edge_accident_count_prior_2y`
  - `edge_bin_accident_count_prior_2y`
  - `recent_activity_flag`
  - `edge_bin_recent_activity_flag`
  - `edge_active_years_prior_recent_3y`
  - `edge_bin_active_years_prior_recent_3y`
  - `edge_accident_count_prior_change_1y`
  - `edge_bin_accident_count_prior_change_1y`
  - `edge_bin_share_of_edge_prior_recent_3y`
- Justificacion:
  - se evitan features con missing estructural alto,
  - se evita meter automaticamente flags/derivadas que son casi reexpresiones de los mismos counts,
  - y se mantiene un bloque interpretable y comparable.

### 5. Milestones

#### Milestone 1
- Purpose:
  Fijar el bloque final de features A2/B2 y validar que todas tienen cobertura completa.
- Files touched:
  `PLANS.md`
- Expected output:
  Especificacion conservadora cerrada.
- Validation:
  Debe quedar claro que A2 y B2 usan exactamente el mismo split y las mismas features.

#### Milestone 2
- Purpose:
  Entrenar Poisson A2 y NB B2 sobre la tabla con lag-safe features.
- Files touched:
  `modeling/config.py`, `modeling/train_lag_safe_baselines.py`
- Expected output:
  Artefactos `poisson_a2_*` y `negative_binomial_b2_*`
- Validation:
  Mismo target, misma tabla, mismo split, mismo bloque de features.

#### Milestone 3
- Purpose:
  Comparar A2 vs B2 y tambien A/B vs A2/B2.
- Files touched:
  `modeling/train_lag_safe_baselines.py`
- Expected output:
  `a2_b2_comparison.csv`, `a2_b2_note.md`, `baseline_ab_vs_a2b2_comparison.csv`
- Validation:
  Debe responder si las lag-safe features mejoran de forma material o marginal y si NB sigue teniendo una ventaja marginal o no.

### 6. Risks
- Riesgo de que las nuevas lag-safe features sean utiles pero muy redundantes con los lags acumulados ya existentes.
- Riesgo de mejora pequena que no cambie el ranking metodologico del baseline.
- Riesgo de sobreinterpretar coeficientes de features de historia reciente como si fueran contexto exogeno.

### 7. Done criteria
- Poisson A2 y NB B2 entrenados.
- Existen todos los artefactos `poisson_a2_*`, `negative_binomial_b2_*`, `a2_b2_*` y `baseline_ab_vs_a2b2_comparison.csv`.
- La comparacion deja claro si las lag-safe features mejoran de verdad validation/test.
- No se cambia ni target, ni split, ni estrategia general del proyecto.

### 8. Open questions
- Si la siguiente iteracion debe seguir con Poisson o NB usando este nuevo bloque.
- Si la siguiente mejora realista debe venir de features contextuales leak-safe mas ricas y no de cambiar otra vez la familia del modelo.

## Active Plan - Modeling Leak-Safe Contextual Features

### 1. Objective
Construir una nueva capa de features contextuales leak-safe para la fase de modelado en Python, manteniendo la misma unidad de panel, el mismo target `accident_count` y el mismo split temporal, sin entrenar todavia el siguiente baseline.

### 2. Why this matters for ROAD-SAFETY
Los baselines A/B y A2/B2 ya mostraron que:
- cambiar Poisson por Negative Binomial no resuelve el cuello de botella principal,
- y anadir mas memoria historica similar solo mejora marginalmente.

El siguiente salto util para ROAD-SAFETY es incorporar senales contextuales reconstruidas de forma segura, para acercar el modelado a la logica futura de riesgo por edge sin introducir leakage ni convertir scores heurísticos en target.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `outputs/modeling/training_table_with_lag_safe_features.parquet`
- `outputs/data/m9_accident_edge_matches.csv`
- `outputs/data/accidentes_tabla_accidente_master.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`

Create:
- `modeling/build_contextual_lag_safe_features.py`
- `outputs/modeling/training_table_with_contextual_lag_safe_features.parquet`
- `outputs/modeling/contextual_lag_safe_feature_registry.csv`
- `outputs/modeling/contextual_lag_safe_feature_summary.csv`
- `outputs/modeling/contextual_lag_safe_feature_note.md`

Modify:
- `modeling/config.py`
- `PLANS.md`

### 4. Assumptions
- La unidad de observacion sigue siendo `edge_id + analysis_year + temporal_bin_4h + is_weekend`.
- El target sigue siendo `accident_count` y no cambia en esta fase.
- M12 no puede usarse directamente como predictor porque sus agregados son full-period accident-backed.
- Parte del contenido de M12 si puede reconstruirse como historia contextual leak-safe si solo se usa informacion previa al `analysis_year`.
- La exposicion de M11 no se reconstruira en esta fase porque requeriria recalcular crosswalk/proxy por cutoff temporal.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar columnas actuales y separar `safe_now`, `unsafe_due_to_leakage` y `potentially_rebuildable_as_lagged`.
- Files touched:
  `modeling/build_contextual_lag_safe_features.py`
- Expected output:
  Registro metodologico de columnas y decision de uso.
- Validation:
  Debe quedar explicito que las columnas full-period de M11/M12 no entran como predictors directos.

#### Milestone 2
- Purpose:
  Reconstruir features contextuales leak-safe con fallback jerarquico.
- Files touched:
  `modeling/build_contextual_lag_safe_features.py`
- Expected output:
  Nuevas features como medias previas de intensidad/ocupacion, soporte contextual y senal dinamica previa.
- Validation:
  Cada feature debe usar solo anos `< analysis_year` y guardar `support_n`, `missing_flag` y `fallback_level`.

#### Milestone 3
- Purpose:
  Generar la nueva training table y artefactos de auditoria.
- Files touched:
  `modeling/build_contextual_lag_safe_features.py`
- Expected output:
  `training_table_with_contextual_lag_safe_features.parquet` y tablas de resumen.
- Validation:
  La nueva tabla debe preservar el numero de filas y la suma del target respecto a `training_table_with_lag_safe_features.parquet`.

### 6. Risks
- Riesgo de leakage si se reintroducen columnas full-period accident-backed sin reconstruccion por cutoff.
- Riesgo de soporte escaso en niveles finos `edge + bin + weekend`, especialmente en zero-only controls.
- Riesgo de sobreajustar el contexto si el fallback no queda trazado y auditable.
- Riesgo de confundir contexto reconstruido desde accidentes pasados con contexto exogeno operativo en tiempo real.

### 7. Done criteria
- Existe una nueva training table con contextual features leak-safe.
- Existe registro de features y resumen de cobertura/missingness/fallback.
- Queda claro que estas features no cambian target ni split.
- Queda claro que aun falta contexto exogeno real aunque esta nueva capa permita probar A3/B3.

### 8. Open questions
- Si la siguiente iteracion A3/B3 deberia usar directamente la version reciente 3y, la acumulada o ambas.
- Si conviene anadir despues imputacion explicita para features de recencia con soporte muy bajo.
- Cuando se incorporara contexto exogeno real no accident-backed para reemplazar o complementar esta aproximacion.

## Active Plan - A3/B3 Contextual Leak-Safe Baselines

### 1. Objective
Entrenar y comparar una nueva iteracion A3/B3 sobre `training_table_with_contextual_lag_safe_features.parquet`, manteniendo el mismo target `accident_count`, el mismo split temporal y un bloque de features contextual corto, leak-safe y no redundante.

### 2. Why this matters for ROAD-SAFETY
Los resultados previos ya fijaron que:
- cambiar Poisson por Negative Binomial no produce una mejora material por si solo,
- y anadir mas memoria historica similar no mejora de forma real en test.

El siguiente paso util es medir si un bloque contextual leak-safe aporta valor mas alla de la historia pura, sin introducir leakage ni saltar todavia a modelos complejos o a routing.

### 3. Files involved
Read:
- `outputs/modeling/training_table_with_contextual_lag_safe_features.parquet`
- `outputs/modeling/contextual_lag_safe_feature_registry.csv`
- `outputs/modeling/contextual_lag_safe_feature_summary.csv`
- `outputs/modeling/poisson_a2_metrics.csv`
- `outputs/modeling/poisson_a2_predictions.csv`
- `outputs/modeling/negative_binomial_b2_metrics.csv`
- `outputs/modeling/negative_binomial_b2_predictions.csv`

Create:
- `modeling/train_contextual_baselines.py`
- `outputs/modeling/poisson_a3_metrics.csv`
- `outputs/modeling/poisson_a3_coefficients.csv`
- `outputs/modeling/poisson_a3_predictions.csv`
- `outputs/modeling/negative_binomial_b3_metrics.csv`
- `outputs/modeling/negative_binomial_b3_coefficients.csv`
- `outputs/modeling/negative_binomial_b3_predictions.csv`
- `outputs/modeling/a3_b3_comparison.csv`
- `outputs/modeling/a3_b3_note.md`
- `outputs/modeling/baseline_a2b2_vs_a3b3_comparison.csv`

Modify:
- `modeling/config.py`
- `PLANS.md`

### 4. Assumptions
- El target sigue siendo `accident_count`.
- El split sigue siendo `train=2016-2022`, `validation=2023`, `test=2024`.
- No entran `reference_only` ni señales full-period accident-backed como predictors directos.
- El bloque contextual debe ser corto y prudente, porque el fallback esta dominado por `road_class_bin_weekend`.

### 5. Milestones

#### Milestone 1
- Purpose:
  Fijar un bloque A3/B3 conservador.
- Files touched:
  `modeling/train_contextual_baselines.py`
- Expected output:
  Set comun de features para A3 y B3.
- Validation:
  Debe dejar fuera features contextuales redundantes y explicar por que.

#### Milestone 2
- Purpose:
  Entrenar Poisson A3 y NB B3 con la misma tabla, el mismo split y las mismas features.
- Files touched:
  `modeling/train_contextual_baselines.py`
- Expected output:
  Artefactos `poisson_a3_*` y `negative_binomial_b3_*`.
- Validation:
  Mismo target, mismo split y mismo bloque de features para ambos modelos.

#### Milestone 3
- Purpose:
  Comparar A3/B3 entre si y tambien contra A2/B2.
- Files touched:
  `modeling/train_contextual_baselines.py`
- Expected output:
  `a3_b3_comparison.csv`, `a3_b3_note.md`, `baseline_a2b2_vs_a3b3_comparison.csv`.
- Validation:
  Debe responder si el bloque contextual leak-safe aporta mejora real, si la mejora cae en ceros o positivos, y si la dominancia del fallback limita las ganancias.

### 6. Risks
- Riesgo de que la señal contextual reciente quede demasiado dominada por el fallback `road_class_bin_weekend`.
- Riesgo de redundancia si se meten a la vez versiones acumuladas y recientes del mismo bloque contextual.
- Riesgo de interpretar como contexto fino de edge lo que en la practica es contexto agregado por clase de via.

### 7. Done criteria
- A3 y B3 entrenados y comparados.
- Existen todos los artefactos `poisson_a3_*`, `negative_binomial_b3_*`, `a3_b3_*` y `baseline_a2b2_vs_a3b3_comparison.csv`.
- Queda claro si el bloque contextual leak-safe aporta valor real o marginal.
- No se cambia target, split, training table base ni estrategia general del proyecto.

### 8. Open questions
- Si la siguiente iteracion debe quedarse con Poisson A3 como baseline principal o mover a NB B3.
- Si merece la pena simplificar aun mas el bloque contextual.
- O si el cuello de botella ya exige contexto exogeno real y no otra vuelta sobre historia/contexto accident-backed.

## Active Plan - Exogenous Context Feature Layer

### 1. Objective
Construir una nueva capa de features exogenas para la tabla de modelado, sin cambiar target, split ni training table base, y sin entrenar todavia el siguiente baseline.

### 2. Why this matters for ROAD-SAFETY
Las comparaciones A/B, A2/B2 y A3/B3 ya fijaron que:
- el cuello de botella actual no es la familia del modelo,
- ni anadir mas historia del mismo tipo,
- sino la pobreza del contexto exogeno real.

ROAD-SAFETY necesita una capa de contexto mas rica y verdaderamente exogena si quiere acercarse a una logica futura de riesgo por edge que vaya mas alla de historia agregada y fallback por `road_class`.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `outputs/modeling/training_table_with_contextual_lag_safe_features.parquet`
- `outputs/data/m8_road_network_edges.csv`
- `outputs/data/m8_road_network_nodes.csv`
- `outputs/tables/m11_crosswalk_quality_summary.csv`
- `outputs/tables/m12_dynamic_signal_note.md`
- `bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`
- `bases de datos/cartografia-base-comunicacions-comunicaciones.csv`
- `bases de datos/network/madrid-latest-free-shp/*`

Create:
- `modeling/build_exogenous_context_features.py`
- `outputs/modeling/training_table_with_exogenous_context_features.parquet`
- `outputs/modeling/exogenous_feature_registry.csv`
- `outputs/modeling/exogenous_feature_summary.csv`
- `outputs/modeling/exogenous_feature_note.md`

Modify:
- `modeling/config.py`
- `PLANS.md`

### 4. Assumptions
- El target sigue siendo `accident_count`.
- El split sigue siendo `train=2016-2022`, `validation=2023`, `test=2024`.
- La base a enriquecer es `training_table_with_contextual_lag_safe_features.parquet`.
- Las nuevas features deben ser exogenas y leak-safe.
- En el entorno Python actual no hay stack geoespacial completo (`geopandas/fiona/shapely/pyogrio`), asi que la primera iteracion se centrara en atributos estaticos/topologicos del edge y calendario determinista.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar las fuentes potenciales y clasificarlas en `usable_now_exogenous`, `usable_with_processing`, `not_usable_now` y `unsafe_due_to_leakage`.
- Files touched:
  `modeling/build_exogenous_context_features.py`
- Expected output:
  Registro claro de fuentes y decision metodologica.
- Validation:
  Debe quedar claro que M11/M12 full-period accident-backed no entran como predictors directos y que la capa lineal de trafico actual sigue sin ser utilizable directamente.

#### Milestone 2
- Purpose:
  Construir un bloque exogeno nuevo a partir de atributos estaticos del edge, topologia de nodos y calendario limpio.
- Files touched:
  `modeling/build_exogenous_context_features.py`
- Expected output:
  Features exogenas nuevas y trazables.
- Validation:
  Cobertura alta, missingness cuantificada y razon leak-safe explicita por feature.

#### Milestone 3
- Purpose:
  Generar la tabla enriquecida y los artefactos de auditoria.
- Files touched:
  `modeling/build_exogenous_context_features.py`
- Expected output:
  `training_table_with_exogenous_context_features.parquet`, registro, resumen y nota.
- Validation:
  La nueva tabla debe preservar filas y target respecto a `training_table_with_contextual_lag_safe_features.parquet`.

### 6. Risks
- Riesgo de llamar exogeno a una capa que en realidad sigue siendo accident-backed.
- Riesgo de quedarnos solo con atributos estaticos del edge y no resolver todavia el hueco de contexto dinamico real.
- Riesgo de introducir demasiadas transformaciones poco interpretables en una fase que todavia es de enrichment, no de tuning fino.

### 7. Done criteria
- Existe una nueva tabla enriquecida con features exogenas.
- Existe un registro que clasifica fuentes y features con cobertura, missingness y razon leak-safe.
- Queda claro que aun no se entrena el siguiente baseline en esta fase.
- Queda claro si ya merece la pena una nueva iteracion o si aun falta contexto exogeno real.

### 8. Open questions
- Si la siguiente iteracion debe probar primero solo atributos estaticos/topologicos del edge.
- Si conviene preparar despues una capa geoprocesada con POIs, land use o traffic controls del extracto OSM.
- Si el siguiente cuello de botella exigira ya meteorologia o trafico exogeno operativo de verdad.

## Active Plan - A4/B4 Exogenous Baseline Comparison

### 1. Objective
Entrenar y comparar:
- `Poisson A4`
- `Negative Binomial B4`

sobre `training_table_with_exogenous_context_features.parquet`, manteniendo el mismo target, el mismo split y el bloque A3 como base, con un subconjunto corto y no redundante de features exogenas.

### 2. Why this matters for ROAD-SAFETY
La fase exogena ya ha dejado una capa nueva con cobertura alta.  
Ahora hace falta comprobar si esa capa aporta mejora real y estable frente a A3/B3, antes de abrir el siguiente frente metodologico hacia contexto dinamico exogeno de verdad.

### 3. Files involved
Read:
- `outputs/modeling/training_table_with_exogenous_context_features.parquet`
- `outputs/modeling/exogenous_feature_registry.csv`
- `outputs/modeling/exogenous_feature_summary.csv`
- `outputs/modeling/poisson_a3_metrics.csv`
- `outputs/modeling/poisson_a3_predictions.csv`
- `outputs/modeling/negative_binomial_b3_metrics.csv`
- `outputs/modeling/negative_binomial_b3_predictions.csv`

Create:
- `modeling/train_exogenous_baselines.py`
- `outputs/modeling/poisson_a4_metrics.csv`
- `outputs/modeling/poisson_a4_coefficients.csv`
- `outputs/modeling/poisson_a4_predictions.csv`
- `outputs/modeling/negative_binomial_b4_metrics.csv`
- `outputs/modeling/negative_binomial_b4_coefficients.csv`
- `outputs/modeling/negative_binomial_b4_predictions.csv`
- `outputs/modeling/a4_b4_comparison.csv`
- `outputs/modeling/a4_b4_note.md`
- `outputs/modeling/baseline_a3b3_vs_a4b4_comparison.csv`
- `outputs/modeling/exogenous_feature_effect_summary.csv`

Modify:
- `modeling/config.py`
- `PLANS.md`

### 4. Assumptions
- Target fijo: `accident_count`.
- Split fijo:
  - `train = 2016-2022`
  - `validation = 2023`
  - `test = 2024`
- Base A3 mantenida:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
  - `log1p_edge_accident_count_prior_recent_3y`
  - `log1p_edge_bin_accident_count_prior_recent_3y`
  - `prior_dynamic_context_signal_recent_3y`
  - `log1p_prior_context_observation_n_recent_3y`
  - `prior_dynamic_context_recent_missing_flag`
  - `ctx_recent_fallback_edge_bin_weekend`
  - `ctx_recent_fallback_edge_bin`
  - `ctx_recent_fallback_global_bin_weekend`
- Subconjunto exogeno corto:
  - `exog_road_class_is_major_flag`
  - `exog_maxspeed_kph_imputed_by_road_class`
  - `exog_maxspeed_missing_flag`
  - `exog_oneway_code_b_flag`
  - `exog_tunnel_flag`
  - `exog_node_degree_mean`
  - `exog_edge_touches_dead_end_flag`
  - `exog_distance_from_network_centroid_km`
  - `exog_temporal_is_night_flag`
  - `exog_temporal_is_weekday_peak_flag`
- Se dejan fuera por prudencia o redundancia:
  - `exog_road_class_hierarchy_score`
  - `exog_road_class_is_local_flag`
  - `exog_road_class_is_link_flag`
  - `exog_maxspeed_kph`
  - `exog_oneway_code_t_flag`
  - `exog_bridge_flag`
  - `exog_layer_abs`
  - `exog_nonzero_layer_flag`
  - `exog_node_degree_max`
  - `exog_node_degree_min`
  - `exog_from_node_degree`
  - `exog_to_node_degree`
  - `exog_edge_touches_intersection_flag`
  - `exog_edge_between_intersections_flag`
  - `exog_orientation_sin`
  - `exog_orientation_cos`
  - `exog_temporal_is_peak_commute_flag`
  - `exog_temporal_is_weekend_night_flag`

### 5. Milestones

#### Milestone 1
- Purpose:
  Fijar el bloque exogeno final y validar que sus columnas son `usable_now_exogenous`.
- Files touched:
  `modeling/train_exogenous_baselines.py`
- Expected output:
  Especificacion A4/B4 cerrada.
- Validation:
  A4 y B4 deben usar exactamente el mismo split y las mismas features.

#### Milestone 2
- Purpose:
  Entrenar Poisson A4 y NB B4 sobre la misma tabla y el mismo bloque de features.
- Files touched:
  `modeling/config.py`, `modeling/train_exogenous_baselines.py`
- Expected output:
  Artefactos `poisson_a4_*` y `negative_binomial_b4_*`.
- Validation:
  Mismo target, mismo split, misma tabla y mismo feature block.

#### Milestone 3
- Purpose:
  Comparar A4/B4 entre si y tambien contra A3/B3.
- Files touched:
  `modeling/train_exogenous_baselines.py`
- Expected output:
  `a4_b4_comparison.csv`, `a4_b4_note.md`, `baseline_a3b3_vs_a4b4_comparison.csv`, `exogenous_feature_effect_summary.csv`.
- Validation:
  Debe dejar claro si el bloque exogeno mejora validation/test y que grupo aporta mas senal: via estatica, topologia, calendario o geometria.

### 6. Risks
- Riesgo de que el bloque exogeno mejore poco porque sigue faltando trafico dinamico alineado a edge.
- Riesgo de colinealidad entre jerarquia viaria y `maxspeed` imputada.
- Riesgo de sobrecargar el bloque con geometria/topologia redundante y erosionar interpretabilidad.

### 7. Done criteria
- Existen todos los artefactos A4/B4 pedidos.
- Queda clara la comparacion A4 vs B4 y A3/B3 vs A4/B4.
- Se identifica si el bloque exogeno aporta mejora real o solo marginal.
- No se cambia target, split, training table base ni estrategia general.

### 8. Open questions
- Si, tras A4/B4, la siguiente mejora debe venir ya de contexto dinamico exogeno real.
- Si merece la pena simplificar aun mas el bloque exogeno antes de incorporar nuevas fuentes.

## Active Plan - Dynamic Exogenous Context Design + Environment Hardening

### 1. Objective
Dejar reproducible el entorno Python de `modeling/` y auditar/diseñar la siguiente capa de `true dynamic exogenous context`, sin entrenar todavia un nuevo modelo.

### 2. Why this matters for ROAD-SAFETY
Tras A4/B4, el cuello de botella ya no es la familia del modelo sino la ausencia de contexto dinamico exogeno real alineado a edge.
Antes de abrir A5/B5, hace falta:
- que el entorno Python sea reproducible,
- que quede claro que fuente dinamica exogena existe de verdad,
- y que se documente con rigor que parte esta lista, que parte es procesable y que parte sigue bloqueada.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `modeling/*.py`
- `outputs/tables/m11_crosswalk_quality_summary.csv`
- `outputs/tables/m11_exposure_note.md`
- `outputs/tables/m12_dynamic_signal_note.md`
- `outputs/data/m11_edge_sensor_crosswalk.csv`
- `outputs/data/m11_historical_exposure_adjusted.csv`
- `outputs/data/m12_edge_context_dynamic_base.csv`
- `bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`
- `bases de datos/network/madrid-latest-free-shp/*`

Create:
- `modeling/requirements.txt`
- `modeling/README.md`
- `modeling/build_dynamic_exogenous_context_audit.py`
- `outputs/modeling/dynamic_exogenous_feature_registry.csv`
- `outputs/modeling/dynamic_exogenous_feature_summary.csv`
- `outputs/modeling/dynamic_exogenous_feature_note.md`

Modify:
- `modeling/config.py`
- `PLANS.md`

Optional:
- `outputs/modeling/training_table_with_true_dynamic_exogenous_features.parquet` solo si aparece una fuente dinamica exogena realmente usable ya mismo.

### 4. Assumptions
- Target, split y training table base no cambian en esta fase.
- No se entrena A5/B5 en este turno.
- El calendario determinista ya esta integrado y no cuenta por si solo como solucion al cuello de botella de contexto dinamico real.
- M11/M12 siguen siendo utiles como referencia metodologica, pero sus outputs full-period accident-backed no pueden entrar como predictor exogeno directo.

### 5. Milestones

#### Milestone 1
- Purpose:
  Endurecer el entorno Python para que `modeling/` sea reproducible.
- Files touched:
  `modeling/requirements.txt`, `modeling/README.md`
- Expected output:
  Dependencias reales fijadas y pasos minimos de ejecucion en VS Code/terminal.
- Validation:
  Las dependencias deben cubrir solo lo realmente usado por los scripts actuales.

#### Milestone 2
- Purpose:
  Auditar fuentes candidatas de contexto dinamico exogeno real.
- Files touched:
  `modeling/build_dynamic_exogenous_context_audit.py`
- Expected output:
  Clasificacion en `usable_now_dynamic_exogenous`, `usable_with_processing`, `not_usable_now`, `unsafe_due_to_leakage`.
- Validation:
  Debe quedar explicitado si existe hoy alguna fuente dinamica exogena realmente alineable a edge sin leakage.

#### Milestone 3
- Purpose:
  Diseñar la integracion leak-safe futura para A5/B5.
- Files touched:
  `modeling/build_dynamic_exogenous_context_audit.py`
- Expected output:
  Registro, resumen y nota tecnica con unidad de integracion, blockers y siguientes pasos.
- Validation:
  Debe separar con claridad:
  - contexto dinamico real usable,
  - contexto procesable pero no operativo,
  - contexto no usable,
  - y salidas accident-backed inseguras.

### 6. Risks
- Riesgo de confundir fuentes temporales existentes con contexto dinamico exogeno realmente usable.
- Riesgo de usar capas de trafico o sensores que siguen apoyadas en accidentes o en geometria no interoperable.
- Riesgo de crear una falsa sensacion de readiness para A5/B5 sin feed temporal real alineado a edge.

### 7. Done criteria
- Existe un `requirements.txt` reproducible para `modeling/`.
- Existe documentacion minima de ejecucion.
- Existen `dynamic_exogenous_feature_registry.csv`, `dynamic_exogenous_feature_summary.csv` y `dynamic_exogenous_feature_note.md`.
- Queda claro si A5/B5 es operable ya o si antes hay que preparar ingestion externa.
- No se entrena ningun modelo nuevo en esta fase.

### 8. Open questions
- Si el siguiente paso debe ser ingestion externa de trafico dinamico real.
- Si merece la pena incorporar meteorologia externa antes que trafico.
- Si el proximo salto debe hacerse sobre un feed historico/snapshot de trafico o sobre integracion online de scoring.

## Active Plan - Pilot Traffic Retraining Comparison

### 1. Objective
Reentrenar de forma comparativa, solo dentro del piloto 2024 con meses 1, 4, 7 y 10, un baseline sin trafico y un baseline con trafico para medir el valor incremental del trafico oficial resumido.

### 2. Why this matters for ROAD-SAFETY
Antes de intentar una integracion mas profunda del trafico al pipeline global, hace falta comprobar si la capa piloto de trafico aporta senal predictiva real dentro del subconjunto donde existe cobertura. Esta fase sirve para eso y solo para eso.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `data/processed/traffic_2024_4months_pilot_training_table.csv`
- `outputs/traffic_2024_4months_pilot_training_table_summary.csv`
- `outputs/traffic_2024_4months_pilot_training_table_missing_reasons.csv`

Create:
- `scripts/traffic/09_train_traffic_pilot_comparative_models.R`
- `outputs/traffic_pilot_baseline_no_traffic_metrics.csv`
- `outputs/traffic_pilot_baseline_with_traffic_metrics.csv`
- `outputs/traffic_pilot_model_comparison.csv`
- `outputs/traffic_pilot_predictions_no_traffic.csv`
- `outputs/traffic_pilot_predictions_with_traffic.csv`
- `outputs/traffic_pilot_model_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- Target del piloto: `pilot_accident_count`.
- Unidad fija: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Split temporal piloto propuesto: train meses `1,4`; validation mes `7`; test mes `10`.
- La comparacion queda restringida al piloto 2024 y no se interpreta como resultado del sistema completo.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar la tabla piloto y fijar target, split y feature blocks.
- Files touched:
  `scripts/traffic/09_train_traffic_pilot_comparative_models.R`
- Expected output:
  Bloques baseline sin trafico y con trafico cerrados.
- Validation:
  Misma unidad, mismo target y mismo split en ambos modelos.

#### Milestone 2
- Purpose:
  Entrenar Poisson y, si la sobredispersion del piloto lo justifica, Negative Binomial, para ambos bloques de features.
- Files touched:
  `scripts/traffic/09_train_traffic_pilot_comparative_models.R`
- Expected output:
  Predicciones y metricas para baseline sin trafico y con trafico.
- Validation:
  El tratamiento de missing de trafico queda documentado y la decision sobre NB queda justificada por diagnostico de dispersion.

#### Milestone 3
- Purpose:
  Comparar de forma limpia sin trafico vs con trafico dentro del piloto.
- Files touched:
  `scripts/traffic/09_train_traffic_pilot_comparative_models.R`
- Expected output:
  `traffic_pilot_model_comparison.csv` y `traffic_pilot_model_note.md`.
- Validation:
  La conclusion debe quedar acotada al piloto y debe separar valor incremental del trafico de cualquier lectura sobre el sistema global.

### 6. Risks
- Riesgo de que la mejora quede sesgada por el caracter parcial del piloto 2024.
- Riesgo de que la cobertura de trafico y sus flags capturen soporte del piloto mas que senal exogena pura.
- Riesgo de que `vmed` anada ruido innecesario si se fuerza su inclusion sin pasar una comprobacion minima de calidad.

### 7. Done criteria
- Existen todos los artefactos del reentrenamiento piloto.
- El target y el split quedan explicitados y defendidos.
- La comparacion sin trafico vs con trafico es directa y reproducible.
- La conclusion final queda claramente limitada al piloto 2024.

### 8. Open questions
- Si la mejora del trafico oficial piloto es suficiente para justificar una integracion mas profunda al pipeline global.
- Si la siguiente mejora debe venir de ampliar cobertura temporal de trafico o de una integracion mas limpia a edge no accident-backed.

## Active Plan - Pilot Traffic Feature Refinement

### 1. Objective
Refinar el bloque de trafico dentro del modelo piloto 2024, manteniendo el mismo target, la misma unidad y el mismo split, para identificar que especificacion de trafico aporta mas valor con el menor coste metodologico.

### 2. Why this matters for ROAD-SAFETY
La comparacion piloto previa ya mostro que el trafico oficial resumido aporta senal incremental real, pero pequena. Antes de intentar una integracion mas profunda, hace falta saber si el valor viene del nucleo `intensidad + ocupacion`, del soporte/calidad, de `vmed` o de transformaciones robustas.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `data/processed/traffic_2024_4months_pilot_training_table.csv`
- `outputs/traffic_pilot_baseline_no_traffic_metrics.csv`
- `outputs/traffic_pilot_baseline_with_traffic_metrics.csv`
- `outputs/traffic_pilot_model_comparison.csv`

Create:
- `scripts/traffic/10_refine_traffic_pilot_feature_specs.R`
- `outputs/traffic_pilot_traffic_feature_spec_comparison.csv`
- `outputs/traffic_pilot_traffic_feature_effect_summary.csv`
- `outputs/traffic_pilot_refined_no_traffic_metrics.csv`
- `outputs/traffic_pilot_refined_with_traffic_metrics.csv`
- `outputs/traffic_pilot_refined_predictions.csv`
- `outputs/traffic_pilot_refined_model_note.md`

Modify:
- `PLANS.md`

### 4. Assumptions
- Target fijo: `pilot_accident_count`.
- Unidad fija: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Split fijo: train meses `1,4`; validation mes `7`; test mes `10`.
- Familia prioritaria: Poisson. No se abre NB salvo error real, porque en el piloto previo no quedo justificado.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar el bloque de trafico y fijar especificaciones conservadoras comparables.
- Files touched:
  `scripts/traffic/10_refine_traffic_pilot_feature_specs.R`
- Expected output:
  Bloques A/B/C/D definidos con el mismo baseline fuera del trafico.
- Validation:
  Debe quedar explicito que cambia en cada especificacion y como se tratan missing, soporte y transformaciones.

#### Milestone 2
- Purpose:
  Entrenar las especificaciones Poisson comparables sin introducir colinealidad silenciosa.
- Files touched:
  `scripts/traffic/10_refine_traffic_pilot_feature_specs.R`
- Expected output:
  Metricas refinadas sin trafico y con trafico, mas predicciones combinadas.
- Validation:
  No debe haber NA en predicciones ni advertencias de rank-deficient fit no resueltas.

#### Milestone 3
- Purpose:
  Comparar especificaciones y recomendar una integracion piloto mas solida.
- Files touched:
  `scripts/traffic/10_refine_traffic_pilot_feature_specs.R`
- Expected output:
  `traffic_pilot_traffic_feature_spec_comparison.csv`, `traffic_pilot_traffic_feature_effect_summary.csv`, `traffic_pilot_refined_model_note.md`.
- Validation:
  Debe quedar claro que especificacion gana, si `vmed` aporta o no, y si la mejora se concentra en positivos, ceros o ambos.

### 6. Risks
- Riesgo de sobreajustar el bloque de trafico en un piloto temporal corto.
- Riesgo de que `vmed` meta ruido pese a tener pocos missing.
- Riesgo de que el soporte de trafico (`n_observations`, `support_n`) mejore solo por capturar cobertura, no por senal contextual sustantiva.

### 7. Done criteria
- Existen todos los artefactos refinados pedidos.
- Las especificaciones comparadas usan la misma base, el mismo target y el mismo split.
- La recomendacion final sobre el bloque de trafico queda clara y acotada al piloto 2024.

### 8. Open questions
- Si la especificacion piloto ganadora justifica una integracion mas profunda al pipeline global.
- Si el siguiente salto debe venir de ampliar cobertura temporal de trafico o de mejorar el alineamiento sensor-edge sin depender de accidentes.

## Active Plan - Python Consolidation Of Pilot Traffic D-Transformed

### 1. Objective
Consolidar en Python, y solo dentro del piloto 2024, la especificacion de trafico `traffic_D_transformed` que sobrevivio en R, para dejarla lista como candidata viva dentro del pipeline principal de modelado.

### 2. Why this matters for ROAD-SAFETY
El modelado principal del proyecto vive en Python. Si el refinamiento del trafico piloto se queda solo en R, no entra de forma limpia en el pipeline principal. Esta fase traduce y valida en Python la especificacion piloto recomendada, sin abrir todavia el modelo global ni routing.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `data/processed/traffic_2024_4months_pilot_training_table.csv`
- `outputs/traffic_pilot_traffic_feature_spec_comparison.csv`
- `outputs/traffic_pilot_traffic_feature_effect_summary.csv`
- `outputs/traffic_pilot_refined_no_traffic_metrics.csv`
- `outputs/traffic_pilot_refined_with_traffic_metrics.csv`
- `outputs/traffic_pilot_refined_model_note.md`

Create:
- `modeling/build_pilot_traffic_input.py`
- `modeling/train_pilot_traffic_baselines.py`
- `outputs/modeling/pilot_traffic_feature_contract.csv`
- `outputs/modeling/pilot_traffic_d_transformed_input.parquet`
- `outputs/modeling/pilot_python_baseline_no_traffic_metrics.csv`
- `outputs/modeling/pilot_python_baseline_with_traffic_metrics.csv`
- `outputs/modeling/pilot_python_traffic_comparison.csv`
- `outputs/modeling/pilot_python_traffic_note.md`

Modify:
- `modeling/config.py`
- `PLANS.md`

### 4. Assumptions
- Alcance restringido al piloto 2024.
- Mismo target: `pilot_accident_count`.
- Misma unidad: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Mismo split: train meses `1,4`; validation `7`; test `10`.
- La version principal del bloque de trafico excluye `vmed`.

### 5. Milestones

#### Milestone 1
- Purpose:
  Formalizar el contrato de features de trafico que sobrevive.
- Files touched:
  `modeling/config.py`, `modeling/build_pilot_traffic_input.py`
- Expected output:
  Contract CSV y parquet listo para modelado.
- Validation:
  Las transformaciones e imputaciones deben reflejar fielmente la logica de R.

#### Milestone 2
- Purpose:
  Entrenar en Python el baseline piloto sin trafico y el baseline piloto con `traffic_D_transformed`.
- Files touched:
  `modeling/train_pilot_traffic_baselines.py`
- Expected output:
  Metricas y comparacion en `outputs/modeling/`.
- Validation:
  Mismo target, misma unidad, mismo split y sin NA en predicciones.

#### Milestone 3
- Purpose:
  Comparar explicitamente la lectura Python con la lectura obtenida en R.
- Files touched:
  `modeling/train_pilot_traffic_baselines.py`
- Expected output:
  `pilot_python_traffic_comparison.csv` y `pilot_python_traffic_note.md`.
- Validation:
  Debe quedar claro si Python reproduce la mejora pequena pero consistente y si `traffic_D_transformed` sobrevive como candidata viva.

### 6. Risks
- Riesgo de pequenas diferencias numericas por cuantiles o codificacion categorica entre R y Python.
- Riesgo de sobreinterpretar un piloto temporal corto como si fuera validacion del sistema completo.
- Riesgo de reabrir `vmed` por inercia pese a que el refinamiento ya lo saco de la version principal.

### 7. Done criteria
- Existen todos los artefactos Python pedidos.
- La especificacion de trafico final queda documentada.
- La comparacion Python vs R deja clara la alineacion o desviacion.
- La conclusion final sigue acotada al piloto 2024.

### 8. Open questions
- Si la especificacion `traffic_D_transformed` debe saltar despues al pipeline global o quedarse solo como modulo piloto mientras no haya mas cobertura temporal.
- Si la siguiente mejora debe venir de mas trafico oficial o de mejor integracion sensor-edge no accident-backed.

## Active Plan - Pilot Traffic Architectural Consolidation In Python

### 1. Objective
Encapsular la rama piloto de trafico 2024 como una capacidad opcional y restringida dentro de `modeling/`, sin mezclarla con el pipeline global por defecto y sin reentrenar modelos nuevos.

### 2. Why this matters for ROAD-SAFETY
El trafico piloto ya sobrevivio metodologicamente y ya se reprodujo en Python. Ahora hace falta evitar que quede como logica ad hoc o que contamine silenciosamente el pipeline global 2016-2024. Esta fase deja claro donde vive el bloque, cuando puede activarse y cuando no.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `modeling/config.py`
- `modeling/README.md`
- `modeling/build_pilot_traffic_input.py`
- `modeling/train_pilot_traffic_baselines.py`
- `data/processed/traffic_2024_4months_pilot_training_table.csv`
- `outputs/modeling/pilot_traffic_feature_contract.csv`
- `outputs/modeling/pilot_traffic_d_transformed_input.parquet`
- `outputs/modeling/pilot_python_traffic_note.md`

Create:
- `modeling/pilot_traffic_block.py`
- `modeling/build_pilot_traffic_architecture.py`
- `outputs/modeling/pilot_traffic_architecture_note.md`
- `outputs/modeling/pilot_traffic_feature_block_contract.csv`
- `outputs/modeling/pilot_traffic_pipeline_gating_rules.csv`
- `outputs/modeling/pilot_vs_global_pipeline_summary.csv`

Modify:
- `modeling/config.py`
- `modeling/README.md`
- `modeling/build_pilot_traffic_input.py`
- `modeling/train_pilot_traffic_baselines.py`
- `PLANS.md`

### 4. Assumptions
- El piloto 2024 sigue siendo una rama separada y no se convierte en default global.
- El contrato vivo del bloque de trafico piloto sigue siendo `traffic_D_transformed`.
- `traffic_vmed_mean` permanece fuera del contrato principal.
- Si se solicita la rama piloto y falla el gating, conviene abortar con mensaje claro antes que caer silenciosamente al pipeline sin trafico.

### 5. Milestones

#### Milestone 1
- Purpose:
  Centralizar constantes, scope, contrato y reglas de gating del bloque de trafico piloto.
- Files touched:
  `modeling/pilot_traffic_block.py`
- Expected output:
  Modulo reusable para builders, trainers y documentacion.
- Validation:
  Debe exponer claramente scope piloto, columnas del bloque y reglas de precondicion.

#### Milestone 2
- Purpose:
  Reusar el nuevo modulo en el builder y trainer del piloto sin reentrenar nada.
- Files touched:
  `modeling/build_pilot_traffic_input.py`, `modeling/train_pilot_traffic_baselines.py`, `modeling/config.py`
- Expected output:
  Scripts piloto apoyados en el mismo contrato/gating y rutas coherentes.
- Validation:
  `py_compile` debe pasar y no debe aparecer logica duplicada critica de scope/split/gating.

#### Milestone 3
- Purpose:
  Generar artefactos de arquitectura y documentacion operativa.
- Files touched:
  `modeling/build_pilot_traffic_architecture.py`, `modeling/README.md`
- Expected output:
  Contract CSV del bloque, gating rules, summary global-vs-pilot y nota tecnica.
- Validation:
  Debe quedar explicito que el piloto es opt-in, restringido a 2024 meses 1,4,7,10 y separado del pipeline global.

### 6. Risks
- Riesgo de dejar el piloto como una rama demasiado acoplada al script de entrenamiento en vez de al pipeline.
- Riesgo de documentar el gating pero no aplicarlo realmente a los builders/trainers piloto.
- Riesgo de que el README sugiera que el trafico piloto forma parte del modelo global cuando no es asi.

### 7. Done criteria
- Existe un modulo central del bloque de trafico piloto.
- Existen artefactos de arquitectura y gating.
- El pipeline global y el piloto quedan diferenciados de forma explicita.
- La documentacion deja claro como activar/desactivar el bloque y cuando no debe usarse.
- No se entrena ningun modelo nuevo en esta fase.

### 8. Open questions
- Si, cuando aumente la cobertura de trafico, el siguiente paso sera promover un bloque mas amplio o abrir una nueva rama intermedia antes del pipeline global.

## Active Plan - Global Scoring Architecture From The Main Modeling Branch

### 1. Objective
Retomar la rama principal del proyecto y construir una arquitectura de scoring global que reutilice el baseline vigente para generar una salida preliminar por unidad de modelado, sin entrar todavia en edge weighting final ni routing.

### 2. Why this matters for ROAD-SAFETY
El pipeline de modelado ya existe y la rama piloto de trafico ya quedo separada. El siguiente paso real hacia el sistema es convertir predicciones del baseline global en una salida de score por edge/unidad temporal que luego pueda conectarse, en fases posteriores, con edge weighting y routing.

### 3. Files involved
Read:
- `AGENTS.md`
- `PROJECT_BRIEF.md`
- `PLANS.md`
- `modeling/config.py`
- `modeling/README.md`
- `modeling/train_baseline.py`
- `modeling/train_exogenous_baselines.py`
- `outputs/modeling/poisson_baseline_metrics.csv`
- `outputs/modeling/negative_binomial_baseline_metrics.csv`
- `outputs/modeling/poisson_a2_metrics.csv`
- `outputs/modeling/negative_binomial_b2_metrics.csv`
- `outputs/modeling/poisson_a3_metrics.csv`
- `outputs/modeling/negative_binomial_b3_metrics.csv`
- `outputs/modeling/poisson_a4_metrics.csv`
- `outputs/modeling/negative_binomial_b4_metrics.csv`
- `outputs/modeling/poisson_a4_predictions.csv`
- `outputs/modeling/negative_binomial_b4_predictions.csv`
- `outputs/modeling/a4_b4_note.md`
- `outputs/modeling/baseline_a3b3_vs_a4b4_comparison.csv`
- `outputs/modeling/pilot_vs_global_pipeline_summary.csv`

Create:
- `modeling/global_scoring_block.py`
- `modeling/score_global_model.py`
- `outputs/modeling/global_scoring_architecture_note.md`
- `outputs/modeling/global_model_branch_summary.csv`
- `outputs/modeling/global_scoring_contract.csv`
- `outputs/modeling/global_scoring_output_prelim.csv`
- `outputs/modeling/global_scoring_validation_summary.csv`
- `outputs/modeling/global_vs_pilot_branch_summary.csv`

Modify:
- `modeling/config.py`
- `modeling/README.md`
- `PLANS.md`

### 4. Assumptions
- La rama global sigue separada del piloto de trafico.
- No se reentrena ningun modelo salvo imposibilidad tecnica real; la prioridad es reutilizar predicciones ya existentes.
- El baseline global vigente se fijara por comparacion explicita de artefactos existentes, no por inercia.
- `predicted_risk_score_prelim` debe ser monotono, interpretable y no debe parecer aun un coste final de routing.

### 5. Milestones

#### Milestone 1
- Purpose:
  Auditar la rama global y fijar el baseline vigente con evidencia reproducible.
- Files touched:
  `modeling/score_global_model.py`
- Expected output:
  `global_model_branch_summary.csv`
- Validation:
  Debe comparar explicitamente A/B, A2/B2, A3/B3 y A4/B4 y dejar un baseline seleccionado.

#### Milestone 2
- Purpose:
  Formalizar el bloque de scoring global separado del entrenamiento y del piloto.
- Files touched:
  `modeling/global_scoring_block.py`, `modeling/config.py`
- Expected output:
  Contrato del scoring, unidad, regla de transformacion y validaciones.
- Validation:
  Debe separar claramente:
  - training table
  - model fitting
  - prediction reuse
  - score transformation
  - future edge weighting
  - future routing

#### Milestone 3
- Purpose:
  Generar la salida preliminar de scoring desde el baseline global seleccionado.
- Files touched:
  `modeling/score_global_model.py`, `modeling/README.md`
- Expected output:
  `global_scoring_output_prelim.csv`, `global_scoring_contract.csv`, `global_scoring_validation_summary.csv`, `global_scoring_architecture_note.md`, `global_vs_pilot_branch_summary.csv`
- Validation:
  La salida debe ser reproducible, unica en la unidad de scoring y dejar claro que no es un edge-weight final.

### 6. Risks
- Riesgo de asumir sin evidencia cual es el baseline global vigente.
- Riesgo de convertir un score preliminar en una pseudo-logica de edge weighting sin querer.
- Riesgo de mezclar accidentalmente la rama piloto con la global por compartir artefactos en `outputs/modeling/`.
- Riesgo de que la transformacion del score pierda interpretabilidad si se sobrediseña.

### 7. Done criteria
- Queda explicitado cual es el baseline global vigente.
- Existe un bloque de scoring global separado del entrenamiento.
- Existe una salida preliminar de score reproducible por unidad global.
- La rama piloto sigue separada y documentada como opcional.
- La salida deja claro que el siguiente paso seria edge weighting, no routing directo.

### 8. Open questions
- Si la futura fase de edge weighting debe usar score raw, score capped o una mezcla politica por ventana temporal.
- Si el edge weighting posterior se apoyara primero en agregacion temporal o en scoring por contexto bajo demanda.
