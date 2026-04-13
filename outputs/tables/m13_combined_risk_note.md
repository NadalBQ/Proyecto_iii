# M13 - Riesgo combinado preliminar por edge/bin

## Regla baseline
- M13 combina `historical_exposure_adjusted_score_prelim` y `dynamic_context_signal_prelim` en la misma escala `0-100`.
- La regla baseline es una media ponderada simple `2/3 historico + 1/3 dinamico`.
- Si el score historico ajustado falta, M13 hace fallback explicito a `historical_score_prelim`.
- Si el componente dinamico falta, M13 no lo inventa y usa solo el historico disponible.

## Por que esta regla es conservadora
- El historico ajustado por exposicion es hoy mas estable porque agrega senal multi-anual.
- El contexto dinamico ya es util, pero sigue siendo mas parcial y accident-backed.
- Los pesos no salen del PCA; se fijan solo como una regla operativa simple y auditable.

## Sensibilidades minimas
- `historical_heavy = 4/5 historico + 1/5 dinamico`.
- `dynamic_heavy = 2/5 historico + 3/5 dinamico`.
- Cambio medio absoluto frente al baseline cuando pesa mas el historico: 4.042
- Cambio medio absoluto frente al baseline cuando pesa mas el dinamico: 8.083
- Entre los 50 edges con mayor cambio de ranking, 47 tienen un solo bin y 46 tienen peso observacional 1; la sensibilidad extrema se concentra sobre todo en soporte contextual muy fino.

## Cobertura resultante
- Filas combinadas: 103556
- Edges cubiertos: 55867
- Filas con historico ajustado usable: 99932
- Filas con fallback a historico raw: 3624
- Filas con fallback solo historico por falta de contexto dinamico: 17777

## Separacion metodologica
- `historical_component` conserva la capa historica preliminar de M10.
- `exposure_adjusted_historical_component` conserva el ajuste preliminar de M11.
- `dynamic_component` conserva la capa contextual de M12.
- `combined_edge_risk_prelim` es solo una combinacion operativa preliminar y trazable de esas piezas.

## Lo que M13 no hace
- No calcula todavia el peso final de routing.
- No incorpora todavia severidad.
- No incorpora todavia meteorologia operativa completa.
- No sustituye a un futuro modelo supervisado si mas adelante entra.
- No ejecuta routing ni coste final de grafo.

- Schema de salida: `m13_schema_v1_combined_edge_risk_prelim_with_sensitivity`.

