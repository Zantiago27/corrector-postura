import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Geometría de la pose.
//
// Sistema de coordenadas de ML Kit (imagen ya rotada a "derecha"):
//   - x crece hacia la DERECHA
//   - y crece hacia ABAJO   (¡ojo! al revés que en matemáticas)
// Todas las funciones son puras: no guardan estado y se pueden probar
// con tests unitarios sin cámara.
// ---------------------------------------------------------------------------

/// Calcula el ángulo en GRADOS formado en el punto B por los
/// segmentos B->A y B->C. Sirve para cualquier articulación.
/// Ejemplo: calcularAngulo(cadera, rodilla, tobillo) = ángulo de la rodilla.
/// Resultado entre 0° (cerrado del todo) y 180° (recto).
double calcularAngulo(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final radianes =
      atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
  var grados = (radianes * 180 / pi).abs();
  if (grados > 180) grados = 360 - grados; // normaliza a 0-180
  return grados;
}

/// Inclinación del segmento [inferior] -> [superior] respecto a la VERTICAL.
///   0°  = el punto superior está justo encima (torso erguido)
///   90° = segmento horizontal (cuerpo acostado)
/// Ejemplo: inclinacionRespectoVertical(hombro, cadera) = cuánto se
/// inclina el torso hacia adelante (o atrás).
double inclinacionRespectoVertical(PoseLandmark superior, PoseLandmark inferior) {
  final dx = superior.x - inferior.x;
  final dy = superior.y - inferior.y; // negativo si "superior" está arriba
  return atan2(dx.abs(), -dy) * 180 / pi;
}

/// Inclinación de la recta A-B respecto a la HORIZONTAL, entre 0° y 90°.
///   0°  = recta horizontal (cuerpo paralelo al suelo)
///   90° = recta vertical (de pie)
double inclinacionRespectoHorizontal(PoseLandmark a, PoseLandmark b) {
  final dx = (b.x - a.x).abs();
  final dy = (b.y - a.y).abs();
  return atan2(dy, dx) * 180 / pi;
}

/// Distancia euclidiana (en píxeles) entre dos puntos.
double distancia(PoseLandmark a, PoseLandmark b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return sqrt(dx * dx + dy * dy);
}

/// ¿Cuánto se separa el punto [p] de la recta que une [a] y [b]?
/// Se mide en VERTICAL y se normaliza por el largo de la recta, así no
/// depende de la distancia a la cámara.
///   > 0  -> [p] está POR DEBAJO de la recta (ej. cadera caída en plancha)
///   < 0  -> [p] está POR ENCIMA de la recta (ej. cadera elevada)
/// Devuelve null si la recta es casi vertical (no tiene sentido medirlo).
double? desviacionDeLinea(PoseLandmark a, PoseLandmark b, PoseLandmark p) {
  final dx = b.x - a.x;
  if (dx.abs() < 1e-6) return null;
  final largo = distancia(a, b);
  if (largo < 1e-6) return null;
  final t = (p.x - a.x) / dx;
  final yRecta = a.y + t * (b.y - a.y);
  return (p.y - yRecta) / largo;
}

/// Atajo para obtener un punto de la pose (o null si no se detectó).
PoseLandmark? punto(Pose pose, PoseLandmarkType tipo) => pose.landmarks[tipo];

// --- Lado izquierdo / derecho ---------------------------------------------

final Map<PoseLandmarkType, PoseLandmarkType> _espejos = _crearEspejos();

Map<PoseLandmarkType, PoseLandmarkType> _crearEspejos() {
  final mapa = <PoseLandmarkType, PoseLandmarkType>{};
  final porNombre = {for (final t in PoseLandmarkType.values) t.name: t};
  for (final t in PoseLandmarkType.values) {
    final n = t.name;
    String? otro;
    if (n.startsWith('left')) otro = 'right${n.substring(4)}';
    if (n.startsWith('right')) otro = 'left${n.substring(5)}';
    mapa[t] = (otro != null ? porNombre[otro] : null) ?? t;
  }
  return mapa;
}

/// Devuelve la articulación del lado contrario
/// (rightKnee -> leftKnee). Las centrales (nose) se devuelven igual.
PoseLandmarkType espejo(PoseLandmarkType tipo) => _espejos[tipo] ?? tipo;