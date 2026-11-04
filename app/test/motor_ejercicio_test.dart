import 'dart:math';

import 'package:corrector_postura/core/geometria.dart';
import 'package:corrector_postura/core/motor_ejercicio.dart';
import 'package:corrector_postura/ejercicios/plancha.dart';
import 'package:corrector_postura/ejercicios/sentadilla.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Poses sintéticas: generamos los puntos a partir de los ángulos que
// queremos simular, sin cámara. Coordenadas de imagen (y hacia abajo).
// ---------------------------------------------------------------------------

PoseLandmark _lm(PoseLandmarkType tipo, double x, double y, bool izquierda) =>
    PoseLandmark(
      type: izquierda ? espejo(tipo) : tipo,
      x: x,
      y: y,
      z: 0,
      likelihood: 0.99,
    );

Pose _pose(List<PoseLandmark> puntos) =>
    Pose(landmarks: {for (final p in puntos) p.type: p});

/// Pose de perfil con la rodilla en [anguloRodilla] y el torso inclinado
/// [torso] grados respecto a la vertical.
Pose poseSentadilla(double anguloRodilla,
    {double torso = 10, bool izquierda = false}) {
  final t = anguloRodilla * pi / 180;
  final f = torso * pi / 180;
  const kx = 300.0, ky = 400.0; // rodilla
  final hx = kx + 100 * sin(t), hy = ky + 100 * cos(t); // cadera
  final sx = hx + 100 * sin(f), sy = hy - 100 * cos(f); // hombro
  return _pose([
    _lm(PoseLandmarkType.rightShoulder, sx, sy, izquierda),
    _lm(PoseLandmarkType.rightHip, hx, hy, izquierda),
    _lm(PoseLandmarkType.rightKnee, kx, ky, izquierda),
    _lm(PoseLandmarkType.rightAnkle, kx, ky + 100, izquierda),
  ]);
}

/// Plancha de perfil. [hundimiento] > 0 baja la cadera (px), < 0 la sube.
Pose posePlancha({double hundimiento = 0}) => _pose([
      _lm(PoseLandmarkType.rightShoulder, 100, 300, false),
      _lm(PoseLandmarkType.rightHip, 250, 300 + hundimiento, false),
      _lm(PoseLandmarkType.rightKnee, 330, 300, false),
      _lm(PoseLandmarkType.rightAnkle, 400, 300, false),
    ]);

/// Persona de pie (para comprobar que la plancha no cuenta tiempo).
Pose poseDePie() => _pose([
      _lm(PoseLandmarkType.rightShoulder, 300, 100, false),
      _lm(PoseLandmarkType.rightHip, 300, 250, false),
      _lm(PoseLandmarkType.rightKnee, 300, 330, false),
      _lm(PoseLandmarkType.rightAnkle, 300, 400, false),
    ]);

/// Alimenta el motor frame a frame con un reloj simulado.
class Simulador {
  final MotorEjercicio motor;
  final Duration paso;
  DateTime reloj = DateTime(2026, 1, 1);
  final List<RepeticionCompletada> reps = [];
  EvaluacionFrame? ultima;

  Simulador(this.motor, {this.paso = const Duration(milliseconds: 50)});

  void frame(Pose pose) {
    ultima = motor.evaluar(pose, instante: reloj);
    final rep = ultima?.repCompletada;
    if (rep != null) reps.add(rep);
    reloj = reloj.add(paso);
  }

  /// Una sentadilla completa: baja de 5° en 5°, se queda abajo y sube.
  void sentadilla(
      {double hasta = 90, double torso = 10, bool izquierda = false}) {
    Pose p(double a) => poseSentadilla(a, torso: torso, izquierda: izquierda);
    for (var a = 175.0; a > hasta; a -= 5) {
      frame(p(a));
    }
    for (var i = 0; i < 4; i++) {
      frame(p(hasta));
    }
    for (var a = hasta; a < 175; a += 5) {
      frame(p(a));
    }
    for (var i = 0; i < 6; i++) {
      frame(p(175));
    }
  }
}

void main() {
  group('Sentadilla: conteo', () {
    test('de pie y quieto (con temblor) no cuenta reps ni marca errores', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      for (var i = 0; i < 40; i++) {
        sim.frame(poseSentadilla(i.isEven ? 169 : 175));
      }
      expect(sim.motor.repeticiones, 0);
      expect(sim.ultima!.erroresActivos, isEmpty);
    });

    test('ruido justo en el umbral de reposo no genera reps fantasma', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      for (var i = 0; i < 40; i++) {
        sim.frame(poseSentadilla(i.isEven ? 157 : 170));
      }
      expect(sim.motor.repeticiones, 0);
    });

    test('sentadilla profunda = 1 rep correcta', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      sim.sentadilla(hasta: 90);
      expect(sim.motor.repeticiones, 1);
      expect(sim.motor.repsCorrectas, 1);
      expect(sim.reps.single.esCorrecta, isTrue);
    });

    test('3 sentadillas seguidas = 3 reps', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      for (var i = 0; i < 3; i++) {
        sim.sentadilla();
      }
      expect(sim.motor.repeticiones, 3);
    });

    test('amago (no baja de 120°) no cuenta', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      sim.sentadilla(hasta: 130);
      expect(sim.motor.repeticiones, 0);
    });

    test('rep imposible de rápida se ignora como ruido', () {
      final sim = Simulador(
        MotorEjercicio(recetaSentadilla),
        paso: const Duration(milliseconds: 10),
      );
      sim.sentadilla();
      expect(sim.motor.repeticiones, 0);
    });

    test('funciona igual si se ve el lado izquierdo', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      sim.sentadilla(izquierda: true);
      expect(sim.motor.ladoIzquierdo, isTrue);
      expect(sim.motor.repsCorrectas, 1);
    });

    test('sin los puntos requeridos devuelve null', () {
      final motor = MotorEjercicio(recetaSentadilla);
      expect(motor.evaluar(_pose([])), isNull);
    });
  });

  group('Sentadilla: forma', () {
    test('sentadilla corta cuenta como "a corregir" con "Baja más"', () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      sim.sentadilla(hasta: 110);
      expect(sim.motor.repeticiones, 1);
      expect(sim.motor.repsIncorrectas, 1);
      expect(sim.reps.single.errores, contains('profundidad_insuficiente'));
      expect(sim.reps.single.errorPrincipal!.mensajeCorto, 'Baja más');
    });

    test('torso muy inclinado se marca y tiene prioridad (severidad alta)',
        () {
      final sim = Simulador(MotorEjercicio(recetaSentadilla));
      sim.sentadilla(hasta: 110, torso: 65);
      final rep = sim.reps.single;
      expect(rep.errores,
          containsAll(['torso_inclinado', 'profundidad_insuficiente']));
      expect(rep.errorPrincipal!.id, 'torso_inclinado');
    });
  });

  group('Plancha', () {
    test('cuerpo recto: el cronómetro avanza', () {
      final sim = Simulador(MotorEjercicio(recetaPlancha));
      for (var i = 0; i < 21; i++) {
        sim.frame(posePlancha());
      }
      expect(sim.motor.segundosMantenidos, closeTo(1.0, 0.01));
      expect(sim.ultima!.formaCorrecta, isTrue);
    });

    test('cadera caída: avisa "Sube la cadera" y pausa el cronómetro', () {
      final sim = Simulador(MotorEjercicio(recetaPlancha));
      for (var i = 0; i < 21; i++) {
        sim.frame(posePlancha(hundimiento: 30));
      }
      expect(sim.ultima!.errorPrincipal!.id, 'cadera_caida');
      expect(sim.motor.segundosMantenidos, lessThan(0.2));
    });

    test('cadera elevada: avisa "Baja la cadera"', () {
      final sim = Simulador(MotorEjercicio(recetaPlancha));
      for (var i = 0; i < 10; i++) {
        sim.frame(posePlancha(hundimiento: -40));
      }
      expect(sim.ultima!.errorPrincipal!.id, 'cadera_elevada');
    });

    test('de pie no cuenta tiempo (fuera de posición)', () {
      final sim = Simulador(MotorEjercicio(recetaPlancha));
      for (var i = 0; i < 21; i++) {
        sim.frame(poseDePie());
      }
      expect(sim.ultima!.enPosicion, isFalse);
      expect(sim.motor.segundosMantenidos, 0);
    });
  });
}
