import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'geometria.dart';

/// Datos que recibe cada regla de forma para decidir si hay error.
class ContextoRegla {
  final Pose pose;
  final double anguloPrincipal; // ej. ángulo de rodilla en sentadilla

  ContextoRegla({required this.pose, required this.anguloPrincipal});

  /// Devuelve un punto de la pose (o null si no se detectó).
  PoseLandmark? p(PoseLandmarkType tipo) => pose.landmarks[tipo];

  /// Calcula el ángulo en el vértice [b] con los puntos [a] y [c].
  /// Devuelve null si falta algún punto.
  double? angulo(PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
    final pa = p(a), pb = p(b), pc = p(c);
    if (pa == null || pb == null || pc == null) return null;
    return calcularAngulo(pa, pb, pc);
  }
}