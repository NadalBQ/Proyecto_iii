import osmnx as ox


class Edge:
    def __init__(self, to: int, weight: float, name: str, length: float = 0.0):
        self.to = to
        self.weight = weight
        self.name = name
        self.length = length


class Graph:
    def __init__(self):
        self.adj = []
        self.coords = []
        self.edge_names = set()


def load_graph(place="Madrid, Spain") -> Graph:
    G_osm = ox.graph_from_place(place, network_type="drive")
    G_osm = ox.add_edge_speeds(G_osm)
    G_osm = ox.add_edge_travel_times(G_osm)

    node_to_idx = {node: i for i, node in enumerate(G_osm.nodes)}
    idx_to_node = list(G_osm.nodes)

    adj = [[] for _ in idx_to_node]
    coords = [None] * len(idx_to_node)
    edge_names = set()

    for node, data in G_osm.nodes(data=True):
        coords[node_to_idx[node]] = (data["y"], data["x"])

    for u, v, data in G_osm.edges(data=True):
        name = data.get("name", "unknown")
        if isinstance(name, list):
            name = name[0]

        edge_names.add(name)
        adj[node_to_idx[u]].append(
            Edge(
                to=node_to_idx[v],
                weight=float(data.get("travel_time", data.get("length", 1.0))),
                name=name,
                length=float(data.get("length", 0.0)),
            )
        )

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
