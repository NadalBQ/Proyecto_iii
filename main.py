# main.py

from src.service import calcular_ruta_optima


def main():
    print("=== SafeRoute CLI ===")

    origen = input("Origen: ")
    destino = input("Destino: ")
    riesgo = float(input("Riesgo maximo (0-10): "))

    result = calcular_ruta_optima(origen, destino, riesgo)

    print("\nResultado:")
    print(result)


if __name__ == "__main__":
    main()
