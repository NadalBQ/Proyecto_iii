from src.graph import load_graph
from src.model import build_and_train_model, build_final_parquet, build_training_xy, train_model
from src.routing import get_route
from src.ui import show_map, show_route
from src.weights import update_edge_weights


def main():
    # 1. Precargar grafos.
    # graph = load_graph("madrid")

    # 2. Construir el parquet y sacar X e y.
    # parquet_path = build_final_parquet("data/raw/accidentes_con_trafico_final.csv")
    # X_train, y_train = build_training_xy(parquet_path)

    # 3. Entrenar el modelo final.
    # model = train_model(X_train, y_train)
    # Alternativa corta:
    # model, parquet_path = build_and_train_model("data/raw/accidentes_con_trafico_final.csv")

    # 4. Guardar o cargar el modelo si hace falta.
    # ...

    # 5. Solicitar input del usuario y preparar datos para predicción.
    # user_input = ...
    # X_user = ...

    # 6. Predecir, actualizar pesos y calcular ruta.
    # risk_scores = ...
    # update_edge_weights(graph)
    # route = get_route(graph, start, end, alpha)

    # 7. Testear o mostrar resultados cuando corresponda.
    # metrics = ...
    # show_map(lat, lon)
    # show_route(route, opacity=0.8)
    return


if __name__ == "__main__":
    main()
