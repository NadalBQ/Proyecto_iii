from src import graph, model, routing, ui, weights
import glob

ui.show_map()
G = graph.load_graph("Valencia")
if len(glob.glob("./models/*.pkl")):
    m = model.load_model(glob.glob("./models/*.pkl")[0])
else:
    m = model.train_model()
try:
    context = weights.get_all_context()
except:
    context = weights.get_offline_context()
alpha = 0 # Importance given to risk by the user
start = (0, 0)
end = (0, 0)
newG = weights.update_edge_weights(G, context)

routes = {} # Risk - route
for i in range(3):
    opacity = 1 if i == 0 else 0.5
    r = routing.get_route(newG, start, end, alpha + i)
    routes[alpha+i] = r
    ui.show_route(r, opacity)
print(routes)
