import math
import pickle
import re
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd
from sklearn.compose import ColumnTransformer
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error
from sklearn.preprocessing import OneHotEncoder, StandardScaler


WEATHER_VALUES = ["despejado", "nublado", "lluvia debil", "lluvia intensa", "nevando", "granizando", "se desconoce"]
TIME_BINS = ["00_03", "04_07", "08_11", "12_15", "16_19", "20_23"]
CATEGORICAL_FEATURES = ["temporal_bin_4h", "weather"]
NUMERIC_FEATURES = ["lat", "lon", "is_weekend", "is_holiday", "intensidad", "ocupacion", "vmed", "street_accident_prior"]
FEATURE_COLUMNS = CATEGORICAL_FEATURES + NUMERIC_FEATURES


def normalize_text(value):
    if value is None or pd.isna(value):
        return ""
    text = unicodedata.normalize("NFKD", str(value).strip().lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def normalize_street_name(value):
    text = normalize_text(value)
    if not text:
        return "unknown"
    for separator in [" num ", " numero ", " km ", " - ", " con "]:
        text = text.split(separator, 1)[0].strip()
    return re.sub(r"\b\d+\b.*$", "", text).strip() or "unknown"


def normalize_weather(value):
    text = normalize_text(value)
    if "lluvia" in text and "intensa" in text:
        return "lluvia intensa"
    if "lluvia" in text:
        return "lluvia debil"
    if "graniz" in text:
        return "granizando"
    if "nev" in text:
        return "nevando"
    if "nubl" in text:
        return "nublado"
    if "despej" in text:
        return "despejado"
    return "se desconoce"


def temporal_bin_from_hour(hour):
    hour = int(hour) % 24
    return TIME_BINS[min(hour // 4, 5)]


def utm30n_to_latlon(easting, northing):
    a, e, e1sq, k0, zone = 6378137.0, 0.081819191, 0.006739497, 0.9996, 30
    x, y = float(easting) - 500000.0, float(northing)
    lon_origin = (zone - 1) * 6 - 177
    m = y / k0
    mu = m / (a * (1 - e**2 / 4 - 3 * e**4 / 64 - 5 * e**6 / 256))
    e1 = (1 - math.sqrt(1 - e**2)) / (1 + math.sqrt(1 - e**2))
    fp = mu + (3 * e1 / 2 - 27 * e1**3 / 32) * math.sin(2 * mu)
    fp += (21 * e1**2 / 16 - 55 * e1**4 / 32) * math.sin(4 * mu)
    fp += (151 * e1**3 / 96) * math.sin(6 * mu) + (1097 * e1**4 / 512) * math.sin(8 * mu)
    c1, t1 = e1sq * math.cos(fp) ** 2, math.tan(fp) ** 2
    r1 = a * (1 - e**2) / (1 - e**2 * math.sin(fp) ** 2) ** 1.5
    n1 = a / math.sqrt(1 - e**2 * math.sin(fp) ** 2)
    d = x / (n1 * k0)
    lat = fp - (n1 * math.tan(fp) / r1) * (
        d**2 / 2
        - (5 + 3 * t1 + 10 * c1 - 4 * c1**2 - 9 * e1sq) * d**4 / 24
        + (61 + 90 * t1 + 298 * c1 + 45 * t1**2 - 252 * e1sq - 3 * c1**2) * d**6 / 720
    )
    lon = math.radians(lon_origin) + (
        d - (1 + 2 * t1 + c1) * d**3 / 6 + (5 - 2 * c1 + 28 * t1 - 3 * c1**2 + 8 * e1sq + 24 * t1**2) * d**5 / 120
    ) / math.cos(fp)
    return math.degrees(lat), math.degrees(lon)


def _weather_column(columns):
    normalized = {normalize_text(column): column for column in columns}
    return normalized.get("estado meteorologico")


def prepare_accidents(csv_path):
    data = pd.read_csv(csv_path, encoding="utf-8-sig")
    weather_column = _weather_column(data.columns)
    required = ["fecha", "hora", "coordenada_x_utm", "coordenada_y_utm", "direccion_unica", "es_festivo"]
    missing = [column for column in required if column not in data.columns]
    if weather_column is None:
        missing.append("estado_meteorologico")
    if missing:
        raise ValueError(f"Missing required CSV columns: {missing}")

    dates = pd.to_datetime(data["fecha"].astype(str) + " " + data["hora"].astype(str), errors="coerce")
    data = data.loc[dates.notna()].copy()
    data["datetime"] = dates.loc[data.index]
    data["analysis_year"] = data["datetime"].dt.year.astype(int)
    data["street_key"] = data["direccion_unica"].map(normalize_street_name)
    data["weather"] = data[weather_column].map(normalize_weather)
    data["temporal_bin_4h"] = data["datetime"].dt.hour.map(temporal_bin_from_hour)
    data["is_weekend"] = (data["datetime"].dt.weekday >= 5).astype(int)
    data["is_holiday"] = pd.to_numeric(data["es_festivo"], errors="coerce").fillna(0).astype(int).clip(0, 1)
    coords = [utm30n_to_latlon(x, y) for x, y in zip(data["coordenada_x_utm"], data["coordenada_y_utm"])]
    data["lat"], data["lon"] = [lat for lat, _ in coords], [lon for _, lon in coords]
    for column in ["intensidad", "ocupacion", "vmed"]:
        data[column] = pd.to_numeric(data[column], errors="coerce") if column in data.columns else np.nan
    return data


def _accident_counts(data, group_columns):
    if "num_expediente" in data.columns:
        return data.groupby(group_columns)["num_expediente"].nunique().reset_index(name="accident_count")
    return data.groupby(group_columns).size().reset_index(name="accident_count")


def _safe_median(values, default=0.0):
    value = pd.to_numeric(values, errors="coerce").median()
    return float(value) if np.isfinite(value) else default


def _defaults(data, streets):
    if "num_expediente" in data.columns:
        street_counts = data.groupby("street_key")["num_expediente"].nunique()
    else:
        street_counts = data["street_key"].value_counts()
    street_defaults = data.groupby("street_key").agg(
        lat=("lat", "median"),
        lon=("lon", "median"),
        intensidad=("intensidad", "median"),
        ocupacion=("ocupacion", "median"),
        vmed=("vmed", "median"),
    )
    street_defaults["street_accident_prior"] = street_counts.reindex(streets).fillna(0)
    global_defaults = {column: _safe_median(data[column]) for column in ["lat", "lon", "intensidad", "ocupacion", "vmed"]}
    global_defaults["street_accident_prior"] = float(street_counts.median()) if len(street_counts) else 0.0
    return street_defaults.reset_index(), global_defaults


def _panel(streets, years=None):
    values = [streets, TIME_BINS, [0, 1], [0, 1], WEATHER_VALUES]
    names = ["street_key", "temporal_bin_4h", "is_weekend", "is_holiday", "weather"]
    if years is not None:
        values = [years] + values
        names = ["analysis_year"] + names
    return pd.MultiIndex.from_product(values, names=names).to_frame(index=False)


def _build_table(accidents, max_streets, years=None, defaults_from=None):
    defaults_from = defaults_from if defaults_from is not None else accidents
    if "num_expediente" in defaults_from.columns:
        street_counts = defaults_from.groupby("street_key")["num_expediente"].nunique()
    else:
        street_counts = defaults_from["street_key"].value_counts()
    streets = street_counts.sort_values(ascending=False).head(max_streets).index.tolist()
    accidents = accidents[accidents["street_key"].isin(streets)].copy()
    default_rows, global_defaults = _defaults(defaults_from[defaults_from["street_key"].isin(streets)], streets)
    group_columns = ["street_key", "temporal_bin_4h", "is_weekend", "is_holiday", "weather"]
    if years is not None:
        group_columns = ["analysis_year"] + group_columns
    table = _panel(streets, years).merge(_accident_counts(accidents, group_columns), on=group_columns, how="left")
    table["accident_count"] = table["accident_count"].fillna(0).astype(float)
    table = table.merge(default_rows, on="street_key", how="left")
    for column, value in global_defaults.items():
        table[column] = pd.to_numeric(table[column], errors="coerce").fillna(value)
    return table


def build_training_table(csv_path, max_streets=1500):
    return _build_table(prepare_accidents(csv_path), max_streets)


def build_temporal_training_table(csv_path, max_streets=100):
    accidents = prepare_accidents(csv_path)
    train = accidents[(accidents["analysis_year"] >= 2016) & (accidents["analysis_year"] <= 2022)].copy()
    table = _build_table(accidents, max_streets, years=list(range(2016, 2025)), defaults_from=train)
    table["split"] = np.where(table["analysis_year"] == 2023, "validation", np.where(table["analysis_year"] == 2024, "test", "train"))
    return table


def _design(preprocessor, X):
    transformed = preprocessor.transform(X)
    if hasattr(transformed, "toarray"):
        transformed = transformed.toarray()
    return sm.add_constant(np.asarray(transformed, dtype=float), has_constant="add")


def _model_metadata(table):
    feature_defaults = {column: _safe_median(table[column]) for column in NUMERIC_FEATURES if column in table.columns}
    street_prior_by_key = {}
    if "street_key" in table.columns and "street_accident_prior" in table.columns:
        street_prior_by_key = table.groupby("street_key")["street_accident_prior"].median().astype(float).to_dict()
    return {
        "feature_defaults": feature_defaults,
        "street_prior_by_key": street_prior_by_key,
    }


def train_model(X, y):
    X = pd.DataFrame(X).copy()
    y = pd.Series(y).copy()
    X = sm.add_constant(X, has_constant="add")
    return smd.NegativeBinomial(y, X).fit(disp=False)


def train_count_model(table, categorical_features=None, numeric_features=None, family="negative_binomial"):
    categorical_features = list(categorical_features or CATEGORICAL_FEATURES)
    numeric_features = list(numeric_features or NUMERIC_FEATURES)
    feature_columns = categorical_features + numeric_features
    X, y = table[feature_columns], table["accident_count"].astype(float)
    preprocessor = ColumnTransformer(
        [("cat", OneHotEncoder(handle_unknown="ignore"), categorical_features), ("num", StandardScaler(), numeric_features)]
    )
    transformed = preprocessor.fit_transform(X)
    if hasattr(transformed, "toarray"):
        transformed = transformed.toarray()
    design = sm.add_constant(np.asarray(transformed, dtype=float), has_constant="add")
    model_family = sm.families.Poisson() if family == "poisson" else sm.families.NegativeBinomial()
    result = sm.GLM(y, design, family=model_family).fit(maxiter=100, disp=False)
    fitted = np.asarray(result.predict(design), dtype=float)
    positive = fitted[np.isfinite(fitted) & (fitted > 0)]
    return {
        "preprocessor": preprocessor,
        "result": result,
        "feature_columns": feature_columns,
        "risk_scale_value": max(float(np.percentile(positive, 95)) if len(positive) else 1.0, 1e-9),
        **_model_metadata(table),
    }


def train_final_model(csv_path, max_streets=1500):
    table = build_training_table(csv_path, max_streets=max_streets)
    model = train_count_model(table)
    return model, table


def predict_counts(model, X):
    X = pd.DataFrame(X)[model["feature_columns"]]
    predictions = np.asarray(model["result"].predict(_design(model["preprocessor"], X)), dtype=float)
    return np.clip(np.nan_to_num(predictions, nan=0.0, posinf=1e9, neginf=0.0), 0.0, None)


def risk_scores(model, X):
    return np.clip(predict_counts(model, X) / model["risk_scale_value"] * 10.0, 0.0, 10.0)


def save_model(model, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as file:
        pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)


def load_model(path):
    with Path(path).open("rb") as file:
        return pickle.load(file)


def predict(model, X):
    if isinstance(model, dict):
        return predict_counts(model, X)

    X = pd.DataFrame(X).copy()
    X = sm.add_constant(X, has_constant="add")
    expected_columns = [column for column in model.model.exog_names if column != "alpha"]
    missing_columns = [column for column in expected_columns if column != "const" and column not in X.columns]
    if missing_columns:
        raise ValueError(f"Missing columns for prediction: {missing_columns}")
    if "const" in expected_columns and "const" not in X.columns:
        X["const"] = 1.0
    return np.asarray(model.predict(X[expected_columns]), dtype=float)


def test_model(model, X, y):
    y = np.asarray(y, dtype=float)
    y_pred = np.clip(np.asarray(predict(model, X), dtype=float), 1e-9, None)
    return {
        "mean_poisson_deviance": float(mean_poisson_deviance(y, y_pred)),
        "mae": float(mean_absolute_error(y, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y, y_pred))),
    }
