import pandas as pd
import glob
import os

# Configuración
CARPETA_DATOS = "C:\\Users\\arche\\Documents\\Ciencia de Datos\\PROY III\\Datos\\Madrid\\Trafico\\*.csv" 
FICHERO_SALIDA = "trafico_madrid_acumulado.csv"

def procesar_incremental():
    ficheros = glob.glob(CARPETA_DATOS)
    
    # 2. FILTRO CRÍTICO: Eliminamos el fichero de salida de la lista de tareas
    # Esto evita que el script se procese a sí mismo
    ficheros_a_procesar = [f for f in ficheros if os.path.basename(f) != FICHERO_SALIDA]
    
    print(f"Encontrados {len(ficheros_a_procesar)} archivos válidos para procesar.")

    for ruta in ficheros_a_procesar:
        nombre = os.path.basename(ruta)
        print(f"Procesando: {nombre}...")
        
        try:
            # Lectura y normalización (formato idelem/id/identif)
            df = pd.read_csv(ruta, sep=';', quotechar='"', encoding='latin-1', on_bad_lines='skip')
            df.columns = [c.lower().strip() for c in df.columns]
            
            if 'id' not in df.columns:
                for col_id in ['idelem', 'identif']:
                    if col_id in df.columns:
                        df = df.rename(columns={col_id: 'id'})
                        break

            if 'fecha' in df.columns:
                df['fecha'] = pd.to_datetime(df['fecha'], errors='coerce')
                df = df.dropna(subset=['fecha'])
                
                # Agregación horaria para reducir volumen
                df_h = df.groupby(['id', df['fecha'].dt.floor('h')]).agg({
                    'intensidad': 'sum',
                    'ocupacion': 'mean',
                    'vmed': 'mean'
                }).reset_index()
                
                # Guardado en modo append
                escribir_cabecera = not os.path.exists(FICHERO_SALIDA)
                df_h.to_csv(
                    FICHERO_SALIDA, 
                    mode='a', 
                    index=False, 
                    sep=';', 
                    header=escribir_cabecera,
                    encoding='utf-8'
                )
                
                print(f"   -> OK: {nombre} añadido.")

        except Exception as e:
            print(f"   -> Error en {nombre}: {e}")
            

procesar_incremental()