import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Calcula el ángulo en GRADOS formado en el punto B por los
/// segmentos B->A y B->C. Sirve para cualquier articulación.
/// Ejemplo: calcularAngulo(cadera, rodilla, tobillo) = ángulo de la rodilla.
double calcularAngulo(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final radianes =
      atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
  var grados = (radianes * 180 / pi).abs();
  if (grados > 180) grados = 360 - grados; // normaliza a 0-180
  return grados;
}

/// Atajo para obtener un punto de la pose (o null si no se detectó).
PoseLandmark? punto(Pose pose, PoseLandmarkType tipo) => pose.landmarks[tipo];