import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'geometria.dart';

/// Datos que recibe cada regla de forma para decidir si hay error.
///
/// Las recetas se escriben con articulaciones del lado DERECHO. Si el motor
/// detecta que se ve mejor el lado izquierdo ([ladoIzquierdo] = true), este
/// contexto "espeja" automáticamente cada consulta. Así una misma receta
/// sirve tanto si el usuario se pone de perfil hacia un lado como hacia el otro.
class ContextoRegla {
  final Pose pose; // pose ya suavizada
  final double valorPrincipal; // ej. ángulo de rodilla en sentadilla
  final bool ladoIzquierdo;

  ContextoRegla({
    required this.pose,
    this.valorPrincipal = 0,
    this.ladoIzquierdo = false,
  });

  /// Copia del contexto con otro valor principal.
  ContextoRegla conValor(double valor) => ContextoRegla(
        pose: pose,
        valorPrincipal: valor,
        ladoIzquierdo: ladoIzquierdo,
      );

  /// Articulación REAL que se consulta (aplica el espejo si corresponde).
  PoseLandmarkType tipoReal(PoseLandmarkType tipo) =>
      ladoIzquierdo ? espejo(tipo) : tipo;

  /// Devuelve un punto de la pose (o null si no se detectó).
  PoseLandmark? p(PoseLandmarkType tipo) => pose.landmarks[tipoReal(tipo)];

  /// Ángulo en el vértice [b] con los puntos [a] y [c] (null si falta alguno).
  double? angulo(PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
    final pa = p(a), pb = p(b), pc = p(c);
    if (pa == null || pb == null || pc == null) return null;
    return calcularAngulo(pa, pb, pc);
  }

  /// Inclinación del segmento [inferior]->[superior] respecto a la vertical.
  double? inclinacion(PoseLandmarkType superior, PoseLandmarkType inferior) {
    final pSup = p(superior), pInf = p(inferior);
    if (pSup == null || pInf == null) return null;
    return inclinacionRespectoVertical(pSup, pInf);
  }

  /// Inclinación de la recta A-B respecto a la horizontal (0° = acostado).
  double? inclinacionHorizontal(PoseLandmarkType a, PoseLandmarkType b) {
    final pa = p(a), pb = p(b);
    if (pa == null || pb == null) return null;
    return inclinacionRespectoHorizontal(pa, pb);
  }

  /// Separación vertical normalizada de [punto] respecto a la recta A-B.
  /// > 0 = por debajo, < 0 = por encima.
  double? desviacion(
      PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType punto) {
    final pa = p(a), pb = p(b), pp = p(punto);
    if (pa == null || pb == null || pp == null) return null;
    return desviacionDeLinea(pa, pb, pp);
  }

  /// Distancia en píxeles entre dos articulaciones.
  double? dist(PoseLandmarkType a, PoseLandmarkType b) {
    final pa = p(a), pb = p(b);
    if (pa == null || pb == null) return null;
    return distancia(pa, pb);
  }
}

/// Resumen de una repetición recién terminada. Lo reciben las reglas que
/// se evalúan "al completar" la rep (ej. ¿bajó lo suficiente?).
class ResumenRep {
  /// Valor agregado de la medida de la regla durante la rep
  /// (el mínimo o el máximo, según declare la regla).
  final double valor;

  /// Cuánto duró la repetición, en segundos.
  final double duracionSegundos;

  const ResumenRep({required this.valor, required this.duracionSegundos});
}