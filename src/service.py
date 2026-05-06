import json
from datetime import datetime
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen
from zoneinfo import ZoneInfo
from difflib import get_close_matches

import numpy as np

try:
    import graph as g
    from routing import dijkstra
    from model import (
        load_model,
        normalize_street_name,
        predict_counts,
        save_model,
        temporal_bin_from_hour,
        train_final_model,
    )
except ImportError:
    import src.graph as g
    from src.routing import dijkstra
    from src.model import (
        load_model,
        normalize_street_name,
        predict_counts,
        save_model,
        temporal_bin_from_hour,
        train_final_model,
    )


_GRAPH = None
_MODEL = None
_STREET_INDEX = None


def get_graph():
    global _GRAPH
    if _GRAPH is None:
        _GRAPH = g.load_graph("Madrid, Spain")
    return _GRAPH


def get_model():
    global _MODEL
    model_path = Path("models/risk_negative_binomial.pkl")
    csv_path = Path("accidentes_con_trafico_final.csv")

    if _MODEL is not None:
        return _MODEL

    if model_path.exists():
        try:
            _MODEL = load_model(model_path)
            return _MODEL
        except Exception:
            _MODEL = None

    if not csv_path.exists():
        raise FileNotFoundError("No hay modelo guardado ni CSV local para entrenarlo.")

    _MODEL, _ = train_final_model(csv_path, max_streets=1500)
    save_model(_MODEL, model_path)
    return _MODEL


def weather_from_openmeteo_code(code):
    try:
        code = int(code)
    except (TypeError, ValueError):
        return "se desconoce"

    if code == 0:
        return "despejado"
    if code in {1, 2, 3, 45, 48}:
        return "nublado"
    if code in {51, 53, 55, 56, 57, 61, 63, 66, 67, 80, 81}:
        return "lluvia debil"
    if code in {65, 82, 95}:
        return "lluvia intensa"
    if code in {71, 73, 75, 77, 85, 86}:
        return "nevando"
    if code in {96, 99}:
        return "granizando"
    return "se desconoce"


def get_current_weather():
    params = urlencode(
        {
            "latitude": 40.4168,
            "longitude": -3.7038,
            "current": "weather_code",
            "timezone": "Europe/Madrid",
        }
    )
    url = f"https://api.open-meteo.com/v1/forecast?{params}"

    try:
        with urlopen(url, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
        return weather_from_openmeteo_code(data.get("current", {}).get("weather_code"))
    except Exception:
        return "se desconoce"


def build_request_context():
    now = datetime.now(ZoneInfo("Europe/Madrid"))
    return {
        "temporal_bin_4h": temporal_bin_from_hour(now.hour),
        "weather": get_current_weather(),
        "is_weekend": int(now.weekday() >= 5),
        "is_holiday": 0,
    }


def build_street_index(graph):
    global _STREET_INDEX
    if _STREET_INDEX is None:
        _STREET_INDEX = list(graph.edge_names)
    return _STREET_INDEX


def fuzzy_street_name(name: str):
    streets = build_street_index(get_graph())
    match = get_close_matches(name, streets, n=1, cutoff=0.6)
    return match[0] if match else name


def normalize_address(address: str):
    parts = address.split(",")
    street = parts[0].strip()
    street_fixed = fuzzy_street_name(street)
    return street_fixed + ("," + ",".join(parts[1:]) if len(parts) > 1 else "")


def build_edge_features(graph, model, context):
    defaults = model.get("feature_defaults", {})
    street_priors = model.get("street_prior_by_key", {})
    default_prior = defaults.get("street_accident_prior", 0.0)

    features = []
    edge_refs = []

    for u, edges in enumerate(graph.adj):
        lat_u, lon_u = graph.coords[u]
        for i, edge in enumerate(edges):
            lat_v, lon_v = graph.coords[edge.to]
            street_key = normalize_street_name(edge.name)

            features.append(
                {
                    "temporal_bin_4h": context["temporal_bin_4h"],
                    "weather": context["weather"],
                    "lat": (lat_u + lat_v) / 2,
                    "lon": (lon_u + lon_v) / 2,
                    "is_weekend": context["is_weekend"],
                    "is_holiday": context["is_holiday"],
                    "intensidad": defaults.get("intensidad", 0.0),
                    "ocupacion": defaults.get("ocupacion", 0.0),
                    "vmed": defaults.get("vmed", 0.0),
                    "street_accident_prior": street_priors.get(street_key, default_prior),
                }
            )
            edge_refs.append((u, i))

    return features, edge_refs


def score_graph_edges(graph, context):
    model = get_model()
    X, edge_refs = build_edge_features(graph, model, context)
    conteos = predict_counts(model, X)
    riesgos = _percentile_risks(conteos)
    return edge_refs, riesgos, _risk_summary(riesgos)


def _percentile_risks(values):
    values = np.asarray(values, dtype=float)
    values = np.nan_to_num(values, nan=0.0, posinf=0.0, neginf=0.0)
    if len(values) <= 1:
        return np.zeros(len(values), dtype=float)
    if float(np.max(values)) == float(np.min(values)):
        return np.zeros(len(values), dtype=float)

    order = np.argsort(values, kind="mergesort")
    ranks = np.empty(len(values), dtype=float)
    ranks[order] = np.arange(len(values), dtype=float)
    return ranks / (len(values) - 1) * 10.0


def _risk_summary(riesgos):
    riesgos = np.asarray(riesgos, dtype=float)
    if len(riesgos) == 0:
        return {"riesgo_min": 0.0, "riesgo_max": 0.0, "riesgo_medio": 0.0}
    return {
        "riesgo_min": round(float(np.min(riesgos)), 2),
        "riesgo_max": round(float(np.max(riesgos)), 2),
        "riesgo_medio": round(float(np.mean(riesgos)), 2),
    }


def build_edge_mask(graph, riesgo_max, context=None, edge_scores=None):
    if edge_scores is None:
        edge_scores = score_graph_edges(graph, context or build_request_context())

    edge_refs, riesgos, _ = edge_scores
    allowed = [[True] * len(graph.adj[u]) for u in range(len(graph.adj))]
    pruned = 0

    for (u, i), riesgo in zip(edge_refs, riesgos):
        if riesgo > riesgo_max:
            allowed[u][i] = False
            pruned += 1

    return allowed, pruned


def _route_edges(graph, path):
    route_edges = []
    for u, v in zip(path, path[1:]):
        candidates = [edge for edge in graph.adj[u] if edge.to == v]
        if candidates:
            route_edges.append(min(candidates, key=lambda edge: edge.weight))
    return route_edges


def _thresholds(riesgo_max):
    riesgo = max(0.0, min(10.0, float(riesgo_max)))
    values = []
    while riesgo < 10:
        values.append(round(riesgo, 1))
        riesgo += 0.5
    values.append(10.0)
    return values


def _error_response(message):
    return {
        "status": "error",
        "mensaje": message,
        "ruta": [],
        "tiempo": None,
        "distancia": None,
        "riesgo_usado": None,
        "riesgo_excedido": False,
        "coordenadas_origen": None,
        "coordenadas_destino": None,
        "tramos": [],
        "aristas_podadas": 0,
        "clima_usado": "se desconoce",
        "riesgo_min": 0.0,
        "riesgo_max": 0.0,
        "riesgo_medio": 0.0,
    }


def calcular_ruta_optima(origen, destino, riesgo_max):
    try:
        G = get_graph()
        context = build_request_context()

        origen = normalize_address(origen)
        destino = normalize_address(destino)

        lat_o, lon_o = g.address_to_coords(origen)
        lat_d, lon_d = g.address_to_coords(destino)

        source = g.get_nearest_node(G, lat_o, lon_o)
        target = g.get_nearest_node(G, lat_d, lon_d)
        riesgo_usuario = max(0.0, min(10.0, float(riesgo_max)))
        edge_scores = None
        risk_info = {"riesgo_min": 0.0, "riesgo_max": 0.0, "riesgo_medio": 0.0}

        for riesgo_actual in _thresholds(riesgo_usuario):
            if riesgo_actual < 10:
                if edge_scores is None:
                    edge_scores = score_graph_edges(G, context)
                    risk_info = edge_scores[2]
                allowed, pruned = build_edge_mask(G, riesgo_actual, edge_scores=edge_scores)
            else:
                allowed, pruned = None, 0

            path, cost = dijkstra(G, source, target, allowed)
            if not path:
                continue

            coords = [G.coords[i] for i in path]
            route_edges = _route_edges(G, path)
            distancia = sum(edge.length for edge in route_edges) / 1000
            tramos = [{"instruccion": f"Sigue por {edge.name}"} for edge in route_edges]
            riesgo_excedido = riesgo_actual > riesgo_usuario
            mensaje = (
                f"No habia ruta con riesgo {riesgo_usuario:.1f}; se uso {riesgo_actual:.1f}"
                if riesgo_excedido
                else "Ruta encontrada"
            )

            return {
                "status": "ok",
                "mensaje": mensaje,
                "ruta": coords,
                "tiempo": round(cost / 60, 1),
                "tiempo_total": cost,
                "distancia": round(distancia, 2),
                "riesgo_usado": round(riesgo_actual, 1),
                "riesgo_excedido": riesgo_excedido,
                "coordenadas_origen": (lat_o, lon_o),
                "coordenadas_destino": (lat_d, lon_d),
                "tramos": tramos,
                "aristas_podadas": pruned,
                "clima_usado": context["weather"],
                **risk_info,
            }

        return _error_response("No hay ruta")
    except Exception as exc:
        return _error_response(str(exc))
