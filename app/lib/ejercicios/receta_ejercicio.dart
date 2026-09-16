import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/contexto_regla.dart';

enum Severidad { alta, media, baja }
enum TipoEjercicio { dinamico, isometrico }

/// Define qué ángulo se usa para detectar una repetición y con qué umbrales.
class DeteccionRepeticion {
  final PoseLandmarkType articulacionA; // ej. cadera
  final PoseLandmarkType articulacionB; // ej. rodilla (vértice del ángulo)
  final PoseLandmarkType articulacionC; // ej. tobillo
  final double umbralAbajo;  // por debajo de este ángulo estás "abajo"
  final double umbralArriba; // por encima de este ángulo estás "arriba"

  const DeteccionRepeticion({
    required this.articulacionA,
    required this.articulacionB,
    required this.articulacionC,
    required this.umbralAbajo,
    required this.umbralArriba,
  });
}

/// Una regla de forma: si la condición se cumple, hay un error de técnica.
/// La condición recibe la pose y los ángulos ya calculados por el motor.
class ReglaForma {
  final String id;
  final String mensaje;
  final Severidad severidad;
  final bool Function(ContextoRegla ctx) condicion;

  const ReglaForma({
    required this.id,
    required this.mensaje,
    required this.severidad,
    required this.condicion,
  });
}

/// La "receta" de un ejercicio: configuración que el motor interpreta.
/// Agregar un ejercicio nuevo = crear otra receta, sin tocar el motor.
class RecetaEjercicio {
  final String id;
  final String nombre;
  final TipoEjercicio tipo;
  final DeteccionRepeticion deteccionRepeticion;
  final List<ReglaForma> reglasForma;

  const RecetaEjercicio({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.deteccionRepeticion,
    this.reglasForma = const [],
  });
}