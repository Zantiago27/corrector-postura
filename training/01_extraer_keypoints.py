"""
01_extraer_keypoints.py — Fase 3, sub-paso 1
=============================================
Convierte tus videos en un CSV de keypoints etiquetados, listo para entrenar
el clasificador de postura.

Idea: por cada frame de cada video, MediaPipe Pose detecta 33 puntos del cuerpo
(los MISMOS que usa ML Kit en la app, porque ambos usan BlazePose). Guardamos
esos puntos NORMALIZADOS (para que no dependan de la distancia a la cámara ni
de dónde esté la persona en el cuadro) junto con la etiqueta correcto/incorrecto.

ORGANIZA TUS VIDEOS ASÍ (la carpeta dice el ejercicio y la etiqueta):
    data/videos/
        squat/correcto/*.mp4
        squat/incorrecto/*.mp4
        curl/correcto/*.mp4
        curl/incorrecto/*.mp4
        plank/correcto/*.mp4
        plank/incorrecto/*.mp4

SALIDA:
    data/keypoints.csv   (una fila por frame con 66 columnas de puntos + metadatos)

CÓMO EJECUTAR
-------------
En Colab o local (recomendado un entorno virtual):
    pip install mediapipe opencv-python pandas numpy
    python 01_extraer_keypoints.py --videos data/videos --salida data/keypoints.csv

Consejos:
    - Graba de PERFIL para sentadilla/plancha (se ven mejor los ángulos).
    - 3-5 videos por carpeta, de 20-40 s, ya es un buen comienzo.
    - Mezcla errores variados en los videos "incorrecto".
"""

import argparse
import csv
import os
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

mp_pose = mp.solutions.pose

# Los 33 puntos de BlazePose. Nos interesan índices clave para normalizar.
HOMBRO_IZQ, HOMBRO_DER = 11, 12
CADERA_IZQ, CADERA_DER = 23, 24
NUM_PUNTOS = 33


def normalizar_landmarks(landmarks):
    """
    Convierte los 33 puntos en un vector invariante a posición y tamaño:
      1) Centra todo en el punto medio de las caderas (traslación).
      2) Escala por el "tamaño del torso" (distancia hombros<->caderas),
         para que dé igual si la persona está cerca o lejos de la cámara.
    Devuelve una lista de 66 números [x0,y0, x1,y1, ...] o None si no se puede.
    """
    pts = np.array([[lm.x, lm.y] for lm in landmarks], dtype=np.float32)

    # Centro = punto medio de las caderas.
    centro = (pts[CADERA_IZQ] + pts[CADERA_DER]) / 2.0
    pts = pts - centro

    # Escala = distancia entre el centro de hombros y el de caderas (torso).
    centro_hombros = (pts[HOMBRO_IZQ] + pts[HOMBRO_DER]) / 2.0
    escala = np.linalg.norm(centro_hombros)  # las caderas ya están en el origen
    if escala < 1e-6:
        return None  # pose degenerada, la saltamos
    pts = pts / escala

    return pts.flatten().tolist()


def procesar_video(ruta_video, pose, ejercicio, etiqueta, escritor, cada_n=2):
    """
    Recorre un video frame a frame, detecta la pose y escribe una fila por
    cada frame válido. `cada_n` salta frames para no generar filas casi
    idénticas (2 = procesa 1 de cada 2).
    """
    cap = cv2.VideoCapture(str(ruta_video))
    if not cap.isOpened():
        print(f"  ⚠ No se pudo abrir: {ruta_video}")
        return 0

    filas = 0
    indice = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        indice += 1
        if indice % cada_n != 0:
            continue

        # MediaPipe trabaja en RGB.
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        resultado = pose.process(rgb)
        if not resultado.pose_landmarks:
            continue

        vector = normalizar_landmarks(resultado.pose_landmarks.landmark)
        if vector is None:
            continue

        # Fila: metadatos + 66 features.
        escritor.writerow([ejercicio, etiqueta, ruta_video.name] + vector)
        filas += 1

    cap.release()
    return filas


def main():
    parser = argparse.ArgumentParser(description="Extrae keypoints de videos a CSV.")
    parser.add_argument("--videos", default="data/videos",
                        help="Carpeta raíz con <ejercicio>/<correcto|incorrecto>/*.mp4")
    parser.add_argument("--salida", default="data/keypoints.csv",
                        help="Ruta del CSV de salida")
    parser.add_argument("--cada_n", type=int, default=2,
                        help="Procesar 1 de cada N frames (2 por defecto)")
    args = parser.parse_args()

    raiz = Path(args.videos)
    if not raiz.exists():
        print(f"ERROR: no existe la carpeta {raiz}. Crea la estructura de videos.")
        return

    # Cabecera del CSV: metadatos + x0,y0,...,x32,y32
    cabecera = ["ejercicio", "etiqueta", "archivo"]
    for i in range(NUM_PUNTOS):
        cabecera += [f"x{i}", f"y{i}"]

    Path(args.salida).parent.mkdir(parents=True, exist_ok=True)
    total = 0

    with open(args.salida, "w", newline="", encoding="utf-8") as f:
        escritor = csv.writer(f)
        escritor.writerow(cabecera)

        # Un detector de pose reutilizable (modo video).
        with mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        ) as pose:
            # Recorre data/videos/<ejercicio>/<etiqueta>/*.mp4
            for dir_ejercicio in sorted(raiz.iterdir()):
                if not dir_ejercicio.is_dir():
                    continue
                ejercicio = dir_ejercicio.name
                for etiqueta in ("correcto", "incorrecto"):
                    dir_etq = dir_ejercicio / etiqueta
                    if not dir_etq.exists():
                        continue
                    videos = [p for p in dir_etq.iterdir()
                              if p.suffix.lower() in (".mp4", ".mov", ".avi", ".mkv")]
                    for ruta in sorted(videos):
                        print(f"Procesando [{ejercicio}/{etiqueta}] {ruta.name} ...")
                        n = procesar_video(ruta, pose, ejercicio, etiqueta,
                                            escritor, cada_n=args.cada_n)
                        print(f"  → {n} frames guardados")
                        total += n

    print(f"\n✅ Listo. {total} filas escritas en {args.salida}")
    if total == 0:
        print("⚠ No se guardó nada. Revisa que haya videos en las subcarpetas "
              "correcto/ e incorrecto/.")


if __name__ == "__main__":
    main()