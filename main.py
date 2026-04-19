from src.graph import load_graph
from src.model import load_model, predict, save_model, test_model, train_model
from src.routing import get_route
from src.ui import show_map, show_route
from src.weights import update_edge_weights


def main():
    # 1. Precargar grafos.
    # graph = load_graph("madrid")

    # 2. Construir los datos del modelo desde cero.
    # X_train = ...
    # y_train = ...

    # 3. Entrenar el modelo final.
    # model = train_model(X_train, y_train)

    # 4. Guardar o cargar el modelo si hace falta.
    # save_model(model, "artifacts/negative_binomial_b4.pkl")
    # model = load_model("artifacts/negative_binomial_b4.pkl")

    # 5. Solicitar input del usuario y preparar datos para predicción.
    # user_input = ...
    # X_user = ...

    # 6. Predecir, actualizar pesos y calcular ruta.
    # risk_scores = predict(model, X_user)
    # update_edge_weights(graph)
    # route = get_route(graph, start, end, alpha)

    # 7. Testear o mostrar resultados cuando corresponda.
    # metrics = test_model(model, X_test, y_test)
    # show_map(lat, lon)
    # show_route(route, opacity=0.8)
    return


if __name__ == "__main__":
    main()
