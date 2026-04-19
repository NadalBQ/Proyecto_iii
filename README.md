# ROAD-SAFETY

Repo del grupo con una superficie de integración mínima:

- `main.py` es el orquestador visible
- `src/model.py` contiene la lógica activa del modelo final

Modelo activo:

- `negative_binomial_b4`
- target: `accident_count`

Comandos públicos:

```powershell
python main.py train
python main.py update
python main.py predict --input <csv-or-parquet>
python main.py evaluate --input <csv-or-parquet> --target-column accident_count
```

Precondiciones locales:

- `train` y `update` requieren `outputs/modeling/training_table_with_exogenous_context_features.parquet`
- `predict` y `evaluate` requieren `artifacts/negative_binomial_b4.pkl`

El repo no reconstruye el parquet desde raw y no depende de `outputs/data/*`.

La documentación corta de estructura y responsabilidades está en [`STRUCTURE.md`](./STRUCTURE.md).
