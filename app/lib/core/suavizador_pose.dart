import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Suaviza los puntos de la pose entre frames para quitar el "temblor".
///
/// ML Kit entrega cada punto con un pequeño ruido: aunque estés quieto,
/// la rodilla "baila" unos píxeles. Ese ruido hace que los ángulos crucen
/// los umbrales de ida y vuelta, y aparecen reps fantasma o avisos que
/// parpadean.
///
/// Usamos una media móvil exponencial (EMA) por coordenada:
///
///     suavizado = anterior + alfa * (nuevo - anterior)
///
/// - alfa = 1.0 -> sin suavizado (sigue al dato crudo)
/// - alfa = 0.6 -> suave pero con poco retraso (valor por defecto)
/// - alfa = 0.3 -> muy suave, pero se nota el retraso en movimientos rápidos
///
/// Trade-off elegido: EMA en vez de filtros más avanzados (One Euro, Kalman)
/// porque tiene un solo parámetro, es fácil de explicar y basta a 15-30 FPS.
class SuavizadorPose {
  final double alfa;

  /// Si pasan más de este tiempo sin frames (ej. saliste de cuadro),
  /// se empieza de cero para no "arrastrar" una posición vieja.
  final Duration reiniciarTras;

  final Map<PoseLandmarkType, PoseLandmark> _anteriores = {};
  DateTime? _ultimoInstante;

  SuavizadorPose({
    this.alfa = 0.6,
    this.reiniciarTras = const Duration(milliseconds: 400),
  }) : assert(alfa > 0 && alfa <= 1);

  /// Devuelve una pose nueva con los puntos suavizados.
  /// La confianza (likelihood) NO se suaviza: se conserva la del frame actual.
  Pose suavizar(Pose pose, DateTime instante) {
    final ultimo = _ultimoInstante;
    if (ultimo != null && instante.difference(ultimo) > reiniciarTras) {
      _anteriores.clear();
    }
    _ultimoInstante = instante;

    final suavizados = <PoseLandmarkType, PoseLandmark>{};
    pose.landmarks.forEach((tipo, actual) {
      final previo = _anteriores[tipo];
      suavizados[tipo] = previo == null
          ? actual
          : PoseLandmark(
              type: tipo,
              x: previo.x + alfa * (actual.x - previo.x),
              y: previo.y + alfa * (actual.y - previo.y),
              z: previo.z + alfa * (actual.z - previo.z),
              likelihood: actual.likelihood,
            );
    });

    _anteriores
      ..clear()
      ..addAll(suavizados);
    return Pose(landmarks: suavizados);
  }

  /// Olvida el historial (al cambiar de cámara, pausar o reiniciar).
  void reiniciar() {
    _anteriores.clear();
    _ultimoInstante = null;
  }
}