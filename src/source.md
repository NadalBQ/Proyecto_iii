# Source Layout

## Public layer

- [`src/model.py`](./model.py) is the public model API.
- [`../main.py`](../main.py) is the only visible orchestrator.

## Internal layer

- `src/internal_model/`
- `pipeline/`

This package contains the minimal internal training bridge required by the
active final model.

The raw-data rebuild pipeline lives in `pipeline/` and remains an internal
implementation detail behind `main.py` and `src/model.py`.

## Boundary rule

Any consumer in the group repo should import model functionality from:

- `src.model`

and not from the internal training or methodological pipeline modules.
