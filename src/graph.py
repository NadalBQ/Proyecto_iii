# src/graph.py

import osmnx as ox


class Edge:
    def __init__(self, to: int, weight: float, name: str):
        self.to = to
        self.weight = weight
        self.name = name  # 🔥 nombre de la calle


class Graph:
    def __init__(self):
        self.adj = []
        self.coords = []
        self.edge_names = set()  # 🔥 índice de calles


def load_graph(place="Madrid, Spain") -> Graph:
    G_osm = ox.graph_from_place(place, network_type="drive")
    G_osm = ox.add_edge_speeds(G_osm)
    G_osm = ox.add_edge_travel_times(G_osm)
    # G_osm = ox.simplify_graph(G_osm)

    node_to_idx = {node: i for i, node in enumerate(G_osm.nodes)}
    idx_to_node = list(G_osm.nodes)

    n = len(idx_to_node)
    adj = [[] for _ in range(n)]
    coords = [None] * n
    edge_names = set()

    for node, data in G_osm.nodes(data=True):
        i = node_to_idx[node]
        coords[i] = (data["y"], data["x"])

    for u, v, data in G_osm.edges(data=True):
        u_i = node_to_idx[u]
        v_i = node_to_idx[v]

        weight = data["travel_time"]

        # 🔥 nombre real
        name = data.get("name", "unknown")
        if isinstance(name, list):
            name = name[0]

        edge_names.add(name)

        adj[u_i].append(Edge(v_i, weight, name))

    G = Graph()
    G.adj = adj
    G.coords = coords
    G.edge_names = edge_names

    return G


def address_to_coords(address: str):
    return ox.geocode(address)


def get_nearest_node(graph: Graph, lat, lon):
    best = None
    best_dist = float("inf")

    for i, (y, x) in enumerate(graph.coords):
        d = (lat - y) ** 2 + (lon - x) ** 2
        if d < best_dist:
            best_dist = d
            best = i

    return best