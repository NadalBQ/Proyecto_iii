
def load_graph(place: str): # desde OSM o un .grapgml
    pass


def get_nearest_node(G, lat, lon):
    pass


def update_edge_weights(G, risk_predictor, context, alpha=1):
    pass


# No se si dejar esta función aquí o ponerla en otra parte
def get_current_context():
    from datetime import datetime

    def get_rain_level():
        pass

    def get_temperature():
        pass

    now = datetime.now()

    context = {
        "hour": now.hour,
        "weekday": now.weekday(),
        "rain": get_rain_level(),
        "temperature": get_temperature()
    } # ...
    return context

