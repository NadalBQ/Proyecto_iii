# Raw Inputs

The raw-data rebuild expects these local files before running:

- `data/raw/accidentes_con_trafico_final.csv`
- `data/external/traffic/estat-transit-temps-real-estado-trafico-tiempo-real.csv`

Optional local cache:

- `data/external/network/madrid-latest-free.shp.zip`

Staging contract inside the disposable compatibility workspace:

- `src/internal_pipeline/.workspace/accidentes_con_trafico_final.csv`
- `src/internal_pipeline/.workspace/bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`
- `src/internal_pipeline/.workspace/bases de datos/network/madrid-latest-free.shp.zip`

If the network zip is missing locally, the upstream R layer may download it.
