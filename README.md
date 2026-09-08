# Corrector de postura de ejercicio con IA

App movil (Flutter) que detecta la pose del usuario en tiempo real,
cuenta repeticiones y evalua la tecnica de 3 ejercicios (sentadilla,
plancha y curl de biceps), dando feedback inmediato. Toda la inferencia
de IA corre en el dispositivo (offline); el backend solo guarda el historial.

## Estructura
- `training/`   Pipeline de entrenamiento en Python/Colab (video -> .tflite)
- `backend/`    API en FastAPI (sesiones e historial)
- `app/`        App Flutter (Android)
- `panel-web/`  Panel web opcional (Vercel)

## Stack
Flutter, ML Kit Pose, TensorFlow Lite, FastAPI, Supabase (Postgres).

## Estado
En desarrollo. Proyecto universitario, metodologia Scrum por fases.
