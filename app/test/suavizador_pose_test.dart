import 'dart:math';

import 'package:corrector_postura/core/suavizador_pose.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Filtro One Euro (Fase I.4): quita el temblor cuando estás quieto y casi no
// retrasa cuando te mueves rápido. Reloj simulado a 20 FPS.
// ---------------------------------------------------------------------------

const _paso = Duration(milliseconds: 50); // 20 FPS

/// "Cuerpo" de 4 puntos (300 px de alto) desplazado [dx] px y con [ruido]
/// px aleatorios en cada coordenada.
Pose _cuerpo({double dx = 0, double ruido = 0, Random? rnd, double z = 0}) {
  double r() => rnd == null ? 0 : (rnd.nextDouble() * 2 - 1) * ruido;
  PoseLandmark lm(PoseLandmarkType t, double x, double y) => PoseLandmark(
      type: t, x: x + dx + r(), y: y + r(), z: z, likelihood: 0.9);
  return Pose(landmarks: {
    for (final p in [
      lm(PoseLandmarkType.rightShoulder, 300, 100),
      lm(PoseLandmarkType.rightHip, 300, 250),
      lm(PoseLandmarkType.rightKnee, 320, 330),
      lm(PoseLandmarkType.rightAnkle, 300, 400),
    ])
      p.type: p,
  });
}

double _desviacion(List<double> v) {
  final media = v.reduce((a, b) => a + b) / v.length;
  return sqrt(v.map((x) => (x - media) * (x - media)).reduce((a, b) => a + b) /
      v.length);
}

void main() {
  final t0 = DateTime(2026, 1, 1);
  const cadera = PoseLandmarkType.rightHip;

  test('alfa: corte bajo suaviza mucho, corte alto casi nada', () {
    expect(SuavizadorPose.alfa(1, 0.05), closeTo(0.239, 0.005));
    expect(SuavizadorPose.alfa(17, 0.05), closeTo(0.842, 0.005));
  });

  test('quieto con ruido: el temblor baja a menos de la mitad', () {
    final s = SuavizadorPose();
    final rnd = Random(1);
    final crudo = <double>[], suave = <double>[];
    for (var i = 0; i < 200; i++) {
      final p = _cuerpo(ruido: 5, rnd: rnd);
      crudo.add(p.landmarks[cadera]!.x);
      suave.add(s.suavizar(p, t0.add(_paso * i)).landmarks[cadera]!.x);
    }
    // Se ignora el primer segundo (el filtro se está "acomodando").
    final dCrudo = _desviacion(crudo.sublist(20));
    final dSuave = _desviacion(suave.sublist(20));
    expect(dSuave, lessThan(0.5 * dCrudo));
  });

  test('movimiento rápido: casi sin retraso (el EMA 0.6 iba 27 px atrás)',
      () {
    final s = SuavizadorPose();
    // 800 px/s (40 px por frame) durante 1 s, sin ruido.
    late double real, filtrado;
    for (var i = 0; i <= 20; i++) {
      real = 40.0 * i;
      filtrado = s
          .suavizar(_cuerpo(dx: real), t0.add(_paso * i))
          .landmarks[cadera]!
          .x;
    }
    final retraso = (300 + real) - filtrado;
    expect(retraso, lessThan(10));
    expect(retraso, greaterThan(0)); // sigue siendo un filtro, no adivina
  });

  test('pose constante: no se mueve ni deriva', () {
    final s = SuavizadorPose();
    for (var i = 0; i < 30; i++) {
      final lm = s.suavizar(_cuerpo(), t0.add(_paso * i)).landmarks[cadera]!;
      expect(lm.x, closeTo(300, 1e-9));
      expect(lm.y, closeTo(250, 1e-9));
    }
  });

  test('tras un hueco de más de 400 ms empieza de cero', () {
    final s = SuavizadorPose();
    for (var i = 0; i < 10; i++) {
      s.suavizar(_cuerpo(), t0.add(_paso * i));
    }
    final despues = s
        .suavizar(_cuerpo(dx: 200), t0.add(const Duration(seconds: 2)))
        .landmarks[cadera]!;
    expect(despues.x, 500); // sin arrastrar la posición vieja
  });

  test('conserva la confianza y suaviza también z', () {
    final s = SuavizadorPose();
    s.suavizar(_cuerpo(z: 0), t0);
    final lm = s.suavizar(_cuerpo(z: 100), t0.add(_paso)).landmarks[cadera]!;
    expect(lm.likelihood, 0.9);
    expect(lm.z, inExclusiveRange(0, 100));
  });

  test('dos frames con el mismo instante no producen NaN', () {
    final s = SuavizadorPose();
    s.suavizar(_cuerpo(), t0);
    final lm = s.suavizar(_cuerpo(dx: 10), t0).landmarks[cadera]!;
    expect(lm.x.isFinite, isTrue);
  });

  test('"rápido" sigue mejor que "por defecto" un movimiento brusco', () {
    double retrasoCon(ParametrosSuavizado p) {
      final s = SuavizadorPose(parametros: p);
      late double filtrado;
      for (var i = 0; i <= 6; i++) {
        filtrado = s
            .suavizar(_cuerpo(dx: 60.0 * i), t0.add(_paso * i))
            .landmarks[cadera]!
            .x;
      }
      return (300 + 360) - filtrado;
    }

    expect(retrasoCon(ParametrosSuavizado.rapido),
        lessThan(retrasoCon(ParametrosSuavizado.porDefecto)));
  });
}