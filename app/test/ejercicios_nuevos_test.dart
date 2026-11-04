import 'dart:math';

import 'package:corrector_postura/core/motor_ejercicio.dart';
import 'package:corrector_postura/ejercicios/flexiones.dart';
import 'package:corrector_postura/ejercicios/instrucciones_ejercicio.dart';
import 'package:corrector_postura/ejercicios/jumping_jacks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Poses sintéticas (coordenadas de imagen: y hacia abajo).
// ---------------------------------------------------------------------------

PoseLandmark _lm(PoseLandmarkType t, double x, double y) =>
    PoseLandmark(type: t, x: x, y: y, z: 0, likelihood: 0.99);

Pose _pose(List<PoseLandmark> puntos) =>
    Pose(landmarks: {for (final p in puntos) p.type: p});

double _rad(double g) => g * pi / 180;

/// Flexión de perfil. [codo] = ángulo del codo; [hundimiento] > 0 baja la
/// cadera (px) y < 0 la sube. Manos y pies en el suelo (y = 400).
Pose poseFlexion(double codo, {double hundimiento = 0}) {
  final h = 200 * sin(_rad(codo) / 2); // altura del hombro (brazo 100 + 100)
  final atras = sqrt(max(0, 100 * 100 - (h / 2) * (h / 2)));
  return _pose([
    _lm(PoseLandmarkType.rightShoulder, 500, 400 - h),
    _lm(PoseLandmarkType.rightElbow, 500 - atras, 400 - h / 2),
    _lm(PoseLandmarkType.rightWrist, 500, 400),
    _lm(PoseLandmarkType.rightHip, 300, 400 - h / 2 + hundimiento),
    _lm(PoseLandmarkType.rightAnkle, 100, 400),
  ]);
}

/// Persona de pie (para comprobar que las flexiones no cuentan).
Pose poseDePie() => _pose([
      _lm(PoseLandmarkType.rightShoulder, 300, 100),
      _lm(PoseLandmarkType.rightElbow, 300, 180),
      _lm(PoseLandmarkType.rightWrist, 300, 250),
      _lm(PoseLandmarkType.rightHip, 300, 250),
      _lm(PoseLandmarkType.rightAnkle, 300, 400),
    ]);

/// Jumping jack de frente. [brazoD]/[brazoI] = ángulo cadera-hombro-muñeca;
/// [piernas] = separación de tobillos / ancho de hombros.
Pose poseJumping(double brazoD, double piernas, {double? brazoI}) {
  final bi = brazoI ?? brazoD;
  return _pose([
    _lm(PoseLandmarkType.rightShoulder, 250, 200),
    _lm(PoseLandmarkType.leftShoulder, 350, 200),
    _lm(PoseLandmarkType.rightHip, 250, 350),
    _lm(PoseLandmarkType.leftHip, 350, 350),
    _lm(PoseLandmarkType.rightWrist, 250 - 150 * sin(_rad(brazoD)),
        200 + 150 * cos(_rad(brazoD))),
    _lm(PoseLandmarkType.leftWrist, 350 + 150 * sin(_rad(bi)),
        200 + 150 * cos(_rad(bi))),
    _lm(PoseLandmarkType.rightAnkle, 300 - piernas * 50, 550),
    _lm(PoseLandmarkType.leftAnkle, 300 + piernas * 50, 550),
  ]);
}

/// Alimenta el motor con un reloj simulado.
class Sim {
  final MotorEjercicio motor;
  DateTime reloj = DateTime(2026, 1, 1);
  final List<RepeticionCompletada> reps = [];
  Sim(this.motor);

  void frame(Pose p) {
    final rep = motor.evaluar(p, instante: reloj)?.repCompletada;
    if (rep != null) reps.add(rep);
    reloj = reloj.add(const Duration(milliseconds: 50));
  }

  /// Flexión completa: baja de [paso] en [paso] grados y vuelve a subir.
  void flexion({
    double hasta = 80,
    double hundimiento = 0,
    double paso = 5,
    int pausa = 4,
  }) {
    Pose p(double a) => poseFlexion(a, hundimiento: hundimiento);
    for (var a = 170.0; a > hasta; a -= paso) {
      frame(p(a));
    }
    for (var i = 0; i < pausa; i++) {
      frame(p(hasta));
    }
    for (var a = hasta; a < 170; a += paso) {
      frame(p(a));
    }
    for (var i = 0; i < 6; i++) {
      frame(p(170));
    }
  }

  /// Jumping jack completo (rápido: 15° por frame).
  void jumping({double brazos = 170, double piernas = 1.8, double? brazoI}) {
    void f(double a) {
      final k = (a - 20) / (brazos - 20);
      final bi = brazoI == null ? null : 20 + (brazoI - 20) * k;
      frame(poseJumping(a, 0.6 + (piernas - 0.6) * k, brazoI: bi));
    }

    for (var a = 20.0; a < brazos; a += 15) {
      f(a);
    }
    for (var i = 0; i < 4; i++) {
      f(brazos);
    }
    for (var a = brazos; a > 20; a -= 15) {
      f(a);
    }
    for (var i = 0; i < 4; i++) {
      f(20);
    }
  }
}

void main() {
  group('Flexiones', () {
    late Sim sim;
    setUp(() => sim = Sim(MotorEjercicio(recetaFlexiones)));

    test('flexión profunda y recta = correcta', () {
      sim.flexion();
      expect(sim.motor.repsCorrectas, 1);
    });

    test('3 flexiones = 3 reps', () {
      for (var i = 0; i < 3; i++) {
        sim.flexion();
      }
      expect(sim.motor.repeticiones, 3);
    });

    test('flexión corta: cuenta, pero "Baja más el pecho"', () {
      sim.flexion(hasta: 100);
      expect(sim.reps.single.errores, ['profundidad_flexion']);
    });

    test('cadera caída: "Sube la cadera"', () {
      sim.flexion(hundimiento: 40);
      expect(sim.reps.single.errorPrincipal!.id, 'cadera_caida');
    });

    test('cadera en V: "Baja la cadera"', () {
      sim.flexion(hundimiento: -50);
      expect(sim.reps.single.errores, contains('cadera_elevada'));
    });

    test('flexión demasiado rápida: "Más despacio"', () {
      sim.flexion(paso: 15, pausa: 1);
      expect(sim.reps.single.errores, contains('muy_rapido'));
    });

    test('de pie no cuenta (fuera de posición)', () {
      for (var i = 0; i < 20; i++) {
        sim.frame(poseDePie());
      }
      expect(sim.motor.repeticiones, 0);
    });
  });

  group('Jumping jacks', () {
    late Sim sim;
    setUp(() => sim = Sim(MotorEjercicio(recetaJumpingJacks)));

    test('jumping jack completo = correcto', () {
      sim.jumping();
      expect(sim.motor.repsCorrectas, 1);
    });

    test('5 seguidos (rápidos) = 5 reps', () {
      for (var i = 0; i < 5; i++) {
        sim.jumping();
      }
      expect(sim.motor.repeticiones, 5);
    });

    test('brazos a medias: "Brazos arriba"', () {
      sim.jumping(brazos: 135);
      expect(sim.reps.single.errores, ['brazos_incompletos']);
    });

    test('piernas poco abiertas: "Abre más las piernas"', () {
      sim.jumping(piernas: 1.0);
      expect(sim.reps.single.errores, ['piernas_cerradas']);
    });

    test('un brazo sube menos: "Brazos parejos"', () {
      sim.jumping(brazoI: 110);
      expect(sim.reps.single.errores, contains('asimetria_brazos'));
    });

    test('usa los dos lados: no espeja', () {
      sim.jumping();
      expect(sim.motor.ladoIzquierdo, isFalse);
    });
  });

  test('los ejercicios nuevos tienen guía propia', () {
    for (final id in ['pushup', 'jumping_jack']) {
      final guia = guiaDe(id);
      expect(guia.pasos.length, greaterThanOrEqualTo(3), reason: id);
      expect(guia.posesClave.length, 2, reason: id);
    }
  });
}