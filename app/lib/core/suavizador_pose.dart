import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Parámetros del filtro One Euro (Fase I.4). Cada receta elige los suyos.
///
/// Idea del filtro: es un EMA cuyo "alfa" cambia con la velocidad.
///   - Quieto o lento  -> corte bajo  -> suaviza mucho (quita el temblor).
///   - Movimiento rápido -> corte alto -> casi no suaviza (sin retraso).
///
///   corte = minCorte + beta * rapidez
///
/// La rapidez se mide en "tamaños del cuerpo por segundo" (no en píxeles),
/// así los parámetros valen igual cerca o lejos de la cámara y con
/// cualquier resolución.
class ParametrosSuavizado {
  /// Frecuencia de corte (Hz) cuando estás quieto. Más bajo = menos temblor
  /// pero más retraso al empezar a moverte.
  final double minCorte;

  /// Cuánto sube el corte con la velocidad. Más alto = menos retraso en
  /// movimientos rápidos (pero deja pasar algo más de ruido).
  final double beta;

  /// Corte (Hz) del filtro que estima la velocidad. Casi nunca se toca.
  final double corteDerivada;

  const ParametrosSuavizado({
    this.minCorte = 1.0,
    this.beta = 6.0,
    this.corteDerivada = 1.0,
  });

  /// Movimientos normales (sentadilla, curl, flexiones, plancha).
  /// Equivale al EMA 0.6 anterior cuando te mueves, pero con ~30 % menos
  /// temblor cuando estás quieto (simulación de la Fase I.4).
  static const porDefecto = ParametrosSuavizado();

  /// Movimientos explosivos (jumping jacks). Sigue mejor los cambios
  /// bruscos, sobre todo si el teléfono analiza pocos FPS.
  static const rapido = ParametrosSuavizado(minCorte: 1.5, beta: 10);
}

/// Suaviza los puntos de la pose entre frames para quitar el "temblor".
///
/// ML Kit entrega cada punto con un pequeño ruido: aunque estés quieto,
/// la rodilla "baila" unos píxeles. Ese ruido hace que los ángulos crucen
/// los umbrales de ida y vuelta, y aparecen reps fantasma o avisos que
/// parpadean.
///
/// Fase I.4: filtro One Euro (Casiez, Roussel y Vogel, CHI 2012) en lugar del
/// EMA de alfa fijo. Con el EMA había que elegir: o temblaba (alfa alto) o
/// iba con retraso en movimientos rápidos (alfa bajo). El One Euro ajusta
/// el alfa en cada frame según la velocidad de cada articulación.
///
/// Por cada articulación y cada frame:
///   1. velocidad ≈ (nuevo - anterior) / dt, suavizada con [corteDerivada].
///   2. corte = minCorte + beta * |velocidad| / tamañoDelCuerpo
///   3. alfa = 1 / (1 + tau / dt), con tau = 1 / (2π · corte)
///   4. suavizado = anterior + alfa * (nuevo - anterior)      (como el EMA)
///
/// Usa el tiempo REAL entre frames (dt), así funciona igual a 10 o a 30 FPS.
class SuavizadorPose {
  final ParametrosSuavizado parametros;

  /// Si pasan más de este tiempo sin frames (ej. saliste de cuadro),
  /// se empieza de cero para no "arrastrar" una posición vieja.
  final Duration reiniciarTras;

  final Map<PoseLandmarkType, PoseLandmark> _anteriores = {};
  final Map<PoseLandmarkType, (double, double)> _velocidades = {};
  DateTime? _ultimoInstante;

  SuavizadorPose({
    this.parametros = ParametrosSuavizado.porDefecto,
    this.reiniciarTras = const Duration(milliseconds: 400),
  });

  /// Devuelve una pose nueva con los puntos suavizados.
  /// La confianza (likelihood) NO se suaviza: se conserva la del frame actual.
  Pose suavizar(Pose pose, DateTime instante) {
    final ultimo = _ultimoInstante;
    if (ultimo != null && instante.difference(ultimo) > reiniciarTras) {
      _anteriores.clear();
      _velocidades.clear();
    }
    // dt en segundos (mínimo 1 ms para no dividir entre cero).
    final double? dt = ultimo == null
        ? null
        : math.max(instante.difference(ultimo).inMicroseconds / 1e6, 0.001);
    _ultimoInstante = instante;

    final escala = _tamanoCuerpo(pose);
    final p = parametros;
    final suavizados = <PoseLandmarkType, PoseLandmark>{};

    for (final MapEntry(key: tipo, value: actual) in pose.landmarks.entries) {
      final previo = _anteriores[tipo];
      if (previo == null || dt == null) {
        // Primer frame de esta articulación: se usa tal cual.
        suavizados[tipo] = actual;
        _velocidades[tipo] = (0.0, 0.0);
        continue;
      }

      // 1) Velocidad (px/s), suavizada para que el ruido no la dispare.
      final (vx0, vy0) = _velocidades[tipo] ?? (0.0, 0.0);
      final ad = alfa(p.corteDerivada, dt);
      final vx = vx0 + ad * ((actual.x - previo.x) / dt - vx0);
      final vy = vy0 + ad * ((actual.y - previo.y) / dt - vy0);
      _velocidades[tipo] = (vx, vy);

      // 2-3) Corte según la rapidez (en tamaños de cuerpo por segundo).
      final rapidez = math.sqrt(vx * vx + vy * vy) / escala;
      final a = alfa(p.minCorte + p.beta * rapidez, dt);

      // 4) Mismo paso que el EMA, pero con alfa variable.
      suavizados[tipo] = PoseLandmark(
        type: tipo,
        x: previo.x + a * (actual.x - previo.x),
        y: previo.y + a * (actual.y - previo.y),
        z: previo.z + a * (actual.z - previo.z),
        likelihood: actual.likelihood,
      );
    }

    _anteriores
      ..clear()
      ..addAll(suavizados);
    return Pose(landmarks: suavizados);
  }

  /// Olvida el historial (al cambiar de cámara, pausar o reiniciar).
  void reiniciar() {
    _anteriores.clear();
    _velocidades.clear();
    _ultimoInstante = null;
  }

  /// Alfa de un filtro paso bajo de primer orden con corte [corteHz] para
  /// un intervalo [dt] (s). Entre 0 (no cambia) y 1 (sigue al dato crudo).
  static double alfa(double corteHz, double dt) {
    final tau = 1 / (2 * math.pi * corteHz);
    return 1 / (1 + tau / dt);
  }

  /// Tamaño del cuerpo en píxeles: el lado mayor de la caja que encierra
  /// todos los puntos. Sirve para medir la velocidad sin depender de la
  /// distancia a la cámara ni de la resolución.
  static double _tamanoCuerpo(Pose pose) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final lm in pose.landmarks.values) {
      minX = math.min(minX, lm.x);
      maxX = math.max(maxX, lm.x);
      minY = math.min(minY, lm.y);
      maxY = math.max(maxY, lm.y);
    }
    if (minX == double.infinity) return 1;
    return math.max(math.max(maxX - minX, maxY - minY), 1);
  }
}