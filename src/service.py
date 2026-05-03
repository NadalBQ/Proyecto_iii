# src/service.py
try:
    import graph as g
    from routing import dijkstra
    from model import load_model, predict
except:
    import src.graph as g
    from src.routing import dijkstra
    from src.model import load_model, predict
from difflib import get_close_matches


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
    if _MODEL is None:
        _MODEL = load_model("model.pkl")
    return _MODEL


def build_street_index(graph):
    global _STREET_INDEX
    if _STREET_INDEX is not None:
        return _STREET_INDEX

    _STREET_INDEX = list(graph.edge_names)
    return _STREET_INDEX


def fuzzy_street_name(name: str):
    streets = build_street_index(get_graph())

    match = get_close_matches(name, streets, n=1, cutoff=0.6)

    return match[0] if match else name


def normalize_address(address: str):
    """
    Corrige SOLO la parte de la calle
    """
    parts = address.split(",")

    street = parts[0].strip()
    street_fixed = fuzzy_street_name(street)

    return street_fixed + ("," + ",".join(parts[1:]) if len(parts) > 1 else "")

# -------------------------
# VARIABLES PARA EL MODELO
# -------------------------
def build_edge_features(graph):
    features = []
    edge_refs = []

    for u in range(len(graph.adj)):
        for i, edge in enumerate(graph.adj[u]):
            lat_u, lon_u = graph.coords[u]

            features.append({
                "lat": lat_u,
                "lon": lon_u
            })

            edge_refs.append((u, i))

    return features, edge_refs


def build_edge_mask(graph, riesgo_max):
    model = get_model()

    X, edge_refs = build_edge_features(graph)
    riesgos = predict(model, X)

    allowed = [
        [True] * len(graph.adj[u])
        for u in range(len(graph.adj))
    ]

    for (u, i), riesgo in zip(edge_refs, riesgos):
        if riesgo > riesgo_max:
            allowed[u][i] = False

    return allowed


# -------------------------
# PIPELINE
# -------------------------
def calcular_ruta_optima(origen, destino, riesgo_max):

    G = get_graph()

    # corregir errores tipográficos
    origen = normalize_address(origen)
    destino = normalize_address(destino)

    lat_o, lon_o = g.address_to_coords(origen)
    lat_d, lon_d = g.address_to_coords(destino)

    source = g.get_nearest_node(G, lat_o, lon_o)
    target = g.get_nearest_node(G, lat_d, lon_d)

    riesgo_actual = riesgo_max

    while riesgo_actual < 11: # Subida automática de riesgo si no existe camino posible con el riesgo deseado
        if riesgo_actual < 10:
            allowed = build_edge_mask(G, riesgo_actual)

            path, cost = dijkstra(G, source, target, allowed)
        else:
            path, cost = dijkstra(G, source, target, None)

        if path:
            coords = [G.coords[i] for i in path]

            return {
                "status": "ok",
                "ruta": coords,
                "tiempo_total": cost,
                "riesgo_usado": riesgo_actual
            }

        riesgo_actual += 1

    return {"status": "error", "message": "No hay ruta"}