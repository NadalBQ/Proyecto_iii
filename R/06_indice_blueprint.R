rs_check_m6_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M6: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m6_inputs <- function(variable_screening, set_screening, m5_result) {
  variable_required_columns <- c("variable", "recommendation", "missing_pct", "zero_pct", "near_zero_variance_flag", "rationale")
  set_required_columns <- c("set_name", "complete_cases_n", "complete_cases_pct", "methodological_comment")
  missing_variable_columns <- setdiff(variable_required_columns, names(variable_screening))
  missing_set_columns <- setdiff(set_required_columns, names(set_screening))

  if (length(missing_variable_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en variable_screening para M6: %s",
        paste(missing_variable_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (length(missing_set_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en set_screening para M6: %s",
        paste(missing_set_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (!all(c("run_summary", "comparison_table") %in% names(m5_result))) {
    stop("M6 necesita `run_summary` y `comparison_table` dentro de m5_result.", call. = FALSE)
  }
}

rs_m6_get_variable_row <- function(variable_screening, variable_name) {
  variable_screening |>
    dplyr::filter(variable == variable_name) |>
    dplyr::slice(1)
}

rs_m6_get_run_summary_row <- function(run_summary, target_run_name) {
  run_summary |>
    dplyr::filter(run_name == target_run_name) |>
    dplyr::slice(1)
}

rs_m6_get_comparison_row <- function(comparison_table, target_question) {
  comparison_table |>
    dplyr::filter(question == target_question) |>
    dplyr::slice(1)
}

rs_build_m6_index_blueprint <- function(variable_screening, set_screening, m5_result) {
  comparison_table <- m5_result$comparison_table
  run_summary <- m5_result$run_summary

  recent_summary <- rs_m6_get_run_summary_row(run_summary, "baseline_recent")
  traffic_comparison <- rs_m6_get_comparison_row(comparison_table, "intensidad_y_ocupacion_mismo_bloque")
  temporal_comparison <- rs_m6_get_comparison_row(comparison_table, "hour_sin_y_hour_cos_eje_temporal_claro")
  vmed_comparison <- rs_m6_get_comparison_row(comparison_table, "cambio_al_anadir_vmed")
  weekend_comparison <- rs_m6_get_comparison_row(comparison_table, "cambio_al_anadir_is_weekend")
  period_comparison <- rs_m6_get_comparison_row(comparison_table, "diferencia_periodo_completo_vs_reciente")
  main_set <- set_screening |>
    dplyr::filter(set_name == "main_continuous") |>
    dplyr::slice(1)

  tibble::tribble(
    ~block_name, ~role_in_risk_logic, ~variables_included, ~variables_excluded, ~reason, ~suggested_combination_rule, ~notes_for_graph_translation,
    "trafico_contexto",
    "baseline_core",
    "intensidad, ocupacion",
    "vmed",
    sprintf(
      "Bloque baseline principal. %s Baseline_recent usa %s casos completos (%.2f%% del set elegible).",
      traffic_comparison$answer,
      format(main_set$complete_cases_n, big.mark = ","),
      main_set$complete_cases_pct
    ),
    "Combinar dentro del bloque con regla anti-doble-conteo: normalizacion robusta por variable, recorte de extremos y agregacion acotada tipo media robusta o max-mean hybrid, no suma plena.",
    "Traducir a atributos segmento-franja horaria a partir de joins con sensores/contexto. Mantener dependencia temporal y evitar duplicar una misma intensidad de trafico en varias capas del grafo.",
    "temporal",
    "baseline_core",
    "hour_sin, hour_cos",
    "hora raw, es_festivo, is_weekend",
    sprintf(
      "Bloque baseline temporal. %s %s",
      temporal_comparison$answer,
      period_comparison$answer
    ),
    "Tratar hour_sin y hour_cos como una sola representacion ciclica del tiempo. La regla de combinacion debe leerlos como bloque conjunto o embedding temporal, no como dos penalizaciones independientes.",
    "Traducir a modulacion dependiente de la hora o bucket temporal del edge. Si mas adelante se discretiza por franjas, el bloque temporal debe alimentar perfiles por hora y no un coste estatico.",
    "moduladores",
    "sensitivity_only",
    "is_weekend",
    "es_festivo",
    sprintf(
      "Bloque de sensibilidad. %s `es_festivo` queda fuera por near-zero variance y 96.38%% de ceros en M4.",
      weekend_comparison$answer
    ),
    "Aplicar como modulador opcional fuera del baseline, por ejemplo como ajuste de escenario o comparacion de robustez. No mezclarlo en el nucleo continuo principal.",
    "En el grafo puede entrar como interruptor de escenario o como version fin_de_semana de los pesos, no como señal basica universal.",
    "velocidad_bajo_revision",
    "under_review_sensitivity",
    "vmed",
    "ninguna exclusion adicional dentro de este bloque",
    sprintf(
      "Variable bajo revision. %s En M4 presenta 19.79%% missing y 92.68%% de ceros.",
      vmed_comparison$answer
    ),
    "No integrarla en el baseline. Si se usa en futuras pruebas, hacerlo como bloque opcional separado tras limpieza y validacion especifica, nunca como sustituto automatico de intensidad/ocupacion.",
    "Antes de pasar al grafo necesita limpieza a nivel sensor/segmento, verificacion de negativos y una regla clara para no duplicar el mismo fenomeno de trafico.",
    "historico_espacial",
    "future_core_block",
    "por definir en la siguiente fase: frecuencia historica por tramo, severidad, exposicion, suavizado espacial",
    "coordenadas raw como entrada directa al score",
    sprintf(
      "Bloque necesario para routing pero aun no operacionalizado en M1-M5. %s El PCA actual solo ha servido para ordenar el bloque contexto/temporal y evitar doble conteo.",
      period_comparison$evidence
    ),
    "Construir fuera del PCA mediante tasas o indicadores historico-espaciales agregados por segmento, con ajuste por exposicion y reglas de suavizado/decay temporal.",
    "Este bloque es el puente real al edge weighting: requiere map-matching/segmentacion, ventanas temporales, severidad y calibracion posterior de la funcion coste."
  )
}

rs_build_m6_variable_status <- function(variable_screening, m5_result) {
  comparison_table <- m5_result$comparison_table
  traffic_comparison <- rs_m6_get_comparison_row(comparison_table, "intensidad_y_ocupacion_mismo_bloque")
  temporal_comparison <- rs_m6_get_comparison_row(comparison_table, "hour_sin_y_hour_cos_eje_temporal_claro")
  vmed_comparison <- rs_m6_get_comparison_row(comparison_table, "cambio_al_anadir_vmed")
  weekend_comparison <- rs_m6_get_comparison_row(comparison_table, "cambio_al_anadir_is_weekend")

  tibble::tribble(
    ~variable, ~status, ~evidence_from_M4_M5, ~rationale,
    "intensidad",
    "baseline",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "intensidad")$rationale,
      traffic_comparison$answer,
      traffic_comparison$evidence
    ),
    "Mantener en el baseline como parte del bloque trafico_contexto, pero sin sumarla a peso pleno con ocupacion.",
    "ocupacion",
    "baseline",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "ocupacion")$rationale,
      traffic_comparison$answer,
      traffic_comparison$evidence
    ),
    "Mantener en el baseline junto con intensidad dentro de un bloque compartido con control de redundancia.",
    "hour_sin",
    "baseline",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "hour_sin")$rationale,
      temporal_comparison$answer,
      temporal_comparison$evidence
    ),
    "Mantener como parte de la codificacion temporal ciclica del baseline; no usar hora raw en paralelo.",
    "hour_cos",
    "baseline",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "hour_cos")$rationale,
      temporal_comparison$answer,
      temporal_comparison$evidence
    ),
    "Mantener como parte de la codificacion temporal ciclica del baseline; debe leerse junto a hour_sin.",
    "is_weekend",
    "sensitivity",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "is_weekend")$rationale,
      weekend_comparison$answer,
      weekend_comparison$evidence
    ),
    "Usarlo solo como modulador de sensibilidad o escenario, no como componente base del score.",
    "vmed",
    "under_review",
    sprintf(
      "M4: %s M5: %s %s",
      rs_m6_get_variable_row(variable_screening, "vmed")$rationale,
      vmed_comparison$answer,
      vmed_comparison$evidence
    ),
    "Mantenerla fuera del baseline. Solo podria volver como sensibilidad separada despues de limpieza y validacion especifica.",
    "es_festivo",
    "excluded",
    sprintf(
      "M4: %s No entra en las corridas M5 por su perfil metodologico de exclusión.",
      rs_m6_get_variable_row(variable_screening, "es_festivo")$rationale
    ),
    "Excluir del indice preliminar porque no aporta un bloque estable ni interpretable dentro del PCA exploratorio actual."
  )
}

rs_build_m6_formula_blueprint <- function() {
  tibble::tribble(
    ~formula_component, ~conceptual_expression, ~purpose, ~current_status,
    "bloque_trafico_contexto",
    "combine_within_block(intensidad, ocupacion)",
    "Representar condicion/contexto de trafico sin duplicar senales vecinas.",
    "baseline_active",
    "bloque_temporal",
    "combine_within_block(hour_sin, hour_cos)",
    "Representar el patron horario de manera ciclica y dependiente del tiempo.",
    "baseline_active",
    "score_baseline",
    "combine_blocks(bloque_trafico_contexto, bloque_temporal)",
    "Score interpretable de referencia para la logica de riesgo antes de sensibilidades.",
    "baseline_active",
    "score_con_sensibilidades",
    "attach_optional_modulators(score_baseline, is_weekend, vmed_review_block)",
    "Escenarios de robustez y pruebas metodologicas sin alterar el nucleo baseline.",
    "sensitivity_only",
    "bloque_historico_espacial",
    "combine_segment_history(exposure_adjusted_events, severity, spatial_smoothing)",
    "Puente futuro entre evidencia de accidentes y riesgo operativo por tramo.",
    "future_required",
    "peso_operativo_arista",
    "routing_cost(edge, time) <- transform(score_baseline + bloque_historico_espacial + moduladores_validados)",
    "Funcion coste final para routing despues de agregacion por segmento, calibracion y validacion.",
    "not_implemented"
  )
}

rs_build_m6_validation_summary <- function(index_blueprint, variable_status, formula_blueprint) {
  tibble::tibble(
    metric = c(
      "blueprint_blocks_n",
      "baseline_variables_n",
      "sensitivity_variables_n",
      "under_review_variables_n",
      "excluded_variables_n",
      "formula_components_n"
    ),
    value = c(
      as.character(nrow(index_blueprint)),
      as.character(sum(variable_status$status == "baseline")),
      as.character(sum(variable_status$status == "sensitivity")),
      as.character(sum(variable_status$status == "under_review")),
      as.character(sum(variable_status$status == "excluded")),
      as.character(nrow(formula_blueprint))
    )
  )
}

rs_write_m6_technical_summary <- function(index_blueprint, variable_status, formula_blueprint, paths) {
  baseline_blocks <- index_blueprint |>
    dplyr::filter(role_in_risk_logic == "baseline_core") |>
    dplyr::pull(block_name)

  sensitivity_variables <- variable_status |>
    dplyr::filter(status == "sensitivity") |>
    dplyr::pull(variable)

  excluded_or_review_variables <- variable_status |>
    dplyr::filter(status %in% c("excluded", "under_review")) |>
    dplyr::transmute(label = paste(variable, status, sep = " -> ")) |>
    dplyr::pull(label)

  summary_lines <- c(
    "# M6 - Diseno preliminar del indice de riesgo ROAD-SAFETY",
    "",
    "## Arquitectura del score baseline",
    sprintf(
      "- El baseline se organiza en bloques, no en una suma plana de variables: `%s`.",
      paste(baseline_blocks, collapse = "`, `")
    ),
    "- Bloque `trafico_contexto`: combina `intensidad` y `ocupacion` con regla anti-doble-conteo dentro del bloque.",
    "- Bloque `temporal`: usa `hour_sin` y `hour_cos` como representacion ciclica conjunta del momento temporal.",
    "- La formula conceptual baseline es:",
    "```text",
    "score_baseline = combine_blocks(",
    "  bloque_trafico_contexto = combine_within_block(intensidad, ocupacion),",
    "  bloque_temporal = combine_within_block(hour_sin, hour_cos)",
    ")",
    "```",
    "",
    "## Arquitectura con sensibilidades",
    sprintf(
      "- Variables en sensibilidad: `%s`.",
      paste(sensitivity_variables, collapse = "`, `")
    ),
    "- `is_weekend` entra como modulador opcional de escenario, no como componente base.",
    "- `vmed` permanece bajo revision y, si se usa, debe entrar como bloque separado de sensibilidad tras limpieza adicional.",
    "- Formula conceptual de sensibilidad:",
    "```text",
    "score_con_sensibilidades = attach_optional_modulators(",
    "  score_baseline,",
    "  weekend_modulator = is_weekend,",
    "  speed_review_block = vmed",
    ")",
    "```",
    "",
    "## Que no conviene sobreponderar junto",
    "- `intensidad` + `ocupacion`: el PCA los situa en el mismo bloque de trafico/contexto.",
    "- `hour_sin` + `hour_cos`: son dos coordenadas de una misma estructura ciclica, no dos ejes temporales independientes para sumar a peso pleno.",
    "- `intensidad`/`ocupacion` + `vmed`: no conviene fusionarlas sin control porque `vmed` altera la estructura y puede duplicar senal de contexto de trafico.",
    "",
    "## Paso de accidente/contexto a tramo/arista",
    "- Primero hay que construir atributos por segmento y franja temporal, no usar el score accidente a accidente de forma directa en routing.",
    "- El bloque `trafico_contexto` se traduce a atributos segmento-tiempo mediante joins con sensores o variables contextuales agregadas.",
    "- El bloque `temporal` se traduce a perfiles dependientes de la hora o a buckets temporales del edge.",
    "- Hace falta una capa nueva `historico_espacial` con exposicion, frecuencia historica, severidad y suavizado espacial a nivel segmento.",
    "- Solo despues puede definirse un `peso_operativo_arista` que combine score conceptual, historial espacial, calibracion y funcion de coste para routing.",
    "- Formula conceptual futura:",
    "```text",
    "peso_operativo_arista(edge, t) = transform(",
    "  score_baseline(edge, t)",
    "  + bloque_historico_espacial(edge)",
    "  + moduladores_validados(edge, t)",
    ")",
    "```",
    "",
    "## Limitaciones",
    "- El PCA ayuda a detectar redundancias, bloques latentes e incompatibilidades de suma ciega.",
    "- El PCA no resuelve pesos finales, causalidad, exposicion, severidad, map-matching ni calibracion para routing.",
    "- Para convertir este blueprint en un peso operativo faltan como minimo: construccion de variables historico-espaciales por segmento, reglas de agregacion temporal, ajuste por exposicion, validacion con red viaria y transformacion final a coste de arista.",
    sprintf(
      "- Variables fuera del baseline actual: `%s`.",
      paste(excluded_or_review_variables, collapse = "`, `")
    ),
    "",
    "## Componentes del blueprint",
    sprintf(
      "- Se han documentado %s bloques y %s componentes de formula conceptual en los CSV de M6.",
      nrow(index_blueprint),
      nrow(formula_blueprint)
    )
  )

  writeLines(
    summary_lines,
    con = file.path(paths$output_tables, "m6_risk_index_blueprint.md"),
    useBytes = TRUE
  )
}

rs_run_m6_indice_blueprint <- function(variable_screening, set_screening, m5_result, paths) {
  rs_check_m6_packages()
  rs_validate_m6_inputs(variable_screening, set_screening, m5_result)

  index_blueprint <- rs_build_m6_index_blueprint(variable_screening, set_screening, m5_result)
  variable_status <- rs_build_m6_variable_status(variable_screening, m5_result)
  formula_blueprint <- rs_build_m6_formula_blueprint()
  validation_summary <- rs_build_m6_validation_summary(index_blueprint, variable_status, formula_blueprint)

  readr::write_csv(
    index_blueprint,
    file.path(paths$output_tables, "m6_index_blueprint.csv")
  )
  readr::write_csv(
    variable_status,
    file.path(paths$output_tables, "m6_final_variable_status.csv")
  )
  readr::write_csv(
    formula_blueprint,
    file.path(paths$output_tables, "m6_conceptual_formula_blueprint.csv")
  )
  readr::write_csv(
    validation_summary,
    file.path(paths$output_tables, "m6_validation_summary.csv")
  )

  rs_write_m6_technical_summary(
    index_blueprint = index_blueprint,
    variable_status = variable_status,
    formula_blueprint = formula_blueprint,
    paths = paths
  )

  list(
    index_blueprint = index_blueprint,
    variable_status = variable_status,
    formula_blueprint = formula_blueprint,
    validation_summary = validation_summary
  )
}
