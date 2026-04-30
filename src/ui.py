
#def show_map(lat, lon):
#    '''Shows the map of the city given the device coordinates'''
#    pass


#def show_route(route, opacity):
#    '''Shows the route on the city map with a certain opacity'''
#    pass

from flask import Flask, render_template, request, jsonify

# IMPORTANTE: Aquí importamos tu lógica desde los otros archivos de tu repo.
# Como ui.py y routing.py están en la misma carpeta (src), importamos así:
from .routing import calcular_ruta_optima # <--- Cambia esto por el nombre real de tu función

# Inicializamos Flask
app = Flask(__name__)

@app.route('/')
def index():
    # Esto cargará el archivo HTML con el mapa de Leaflet
    return render_template('index.html')

@app.route('/calcular_ruta', methods=['POST'])
def interfaz_calcular_ruta():
    # 1. Extraemos los inputs del usuario (que vienen desde el navegador)
    datos = request.json
    
    origen_usuario = datos.get('origen')
    destino_usuario = datos.get('destino')
    
    try:
        riesgo_usuario = float(datos.get('riesgo_max'))
    except (TypeError, ValueError):
        riesgo_usuario = 0.0

    # 2. Le pasamos estos datos a TU algoritmo (en routing.py o main.py)
    # Tu función debe devolver el diccionario con las coordenadas exactas, tiempos, etc.
    resultado = calcular_ruta_optima(origen_usuario, destino_usuario, riesgo_usuario)

    # 3. Devolvemos el resultado al mapa para que lo dibuje
    return jsonify(resultado)

# Esta función permite arrancar el servidor web si decides ejecutar ui.py directamente
def start_ui():
    app.run(debug=True)

if __name__ == '__main__':
    start_ui()
