import 'dart:math';

import 'package:corrector_postura/core/motor_ejercicio.dart';
import 'package:corrector_postura/core/racha.dart';
import 'package:corrector_postura/ejercicios/receta_ejercicio.dart';
import 'package:corrector_postura/ejercicios/sentadilla.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Fase I.5: las fases y los errores se confirman por TIEMPO, así la app se
// comporta igual a 10, 20 o 40 FPS.
// ---------------------------------------------------------------------------

final _t0 = DateTime(2026, 1, 1);

PoseLandmark _lm(PoseLandmarkType t, double x, double y) =>
    PoseLandmark(type: t, x: x, y: y, z: 0, likelihood: 0.99);

/// Sentadilla de perfil (misma geometría que motor_ejercicio_test).
Pose _sentadilla(double rodilla) {
  final t = rodilla * pi / 180, f = 10 * pi / 180;
  const kx = 300.0, ky = 400.0;
  final hx = kx + 100 * sin(t), hy = ky + 100 * cos(t);
  final sx = hx + 100 * sin(f), sy = hy - 100 * cos(f);
  return Pose(landmarks: {
    for (final p in [
      _lm(PoseLandmarkType.rightShoulder, sx, sy),
      _lm(PoseLandmarkType.rightHip, hx, hy),
      _lm(PoseLandmarkType.rightKnee, kx, ky),
      _lm(PoseLandmarkType.rightAnkle, kx, ky + 100),
    ])
      p.type: p,
  });
}

/// Cuerpo horizontal; [hundimiento] > 0 baja la cadera.
Pose _tabla({double hundimiento = 0}) => Pose(landmarks: {
      for (final p in [
        _lm(PoseLandmarkType.rightShoulder, 100, 300),
        _lm(PoseLandmarkType.rightHip, 250, 300 + hundimiento),
        _lm(PoseLandmarkType.rightKnee, 330, 300),
        _lm(PoseLandmarkType.rightAnkle, 400, 300),
      ])
        p.type: p,
    });

/// Receta mínima de prueba: isométrica con una regla instantánea de
/// framesMinimos = 3 (por defecto → 100 ms) y otra con 300 ms explícitos.
final _recetaPrueba = RecetaEjercicio(
  id: 'prueba',
  nombre: 'Prueba',
  tipo: TipoEjercicio.isometrico,
  puntosRequeridos: const [
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightAnkle,
  ],
  reglasForma: [
    ReglaForma.instantanea(
      id: 'cadera_caida',
      mensajeCorto: 'Sube la cadera',
      mensajeLargo: '-',
      severidad: Severidad.alta,
      condicion: (ctx) {
        final d = ctx.desviacion(PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHip);
        return d != null && d > 0.06;
      },
    ),
    ReglaForma.instantanea(
      id: 'lenta',
      mensajeCorto: 'Lenta',
      mensajeLargo: '-',
      severidad: Severidad.baja,
      msMinimos: 300,
      condicion: (ctx) {
        final d = ctx.desviacion(PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHip);
        return d != null && d > 0.06;
      },
    ),
  ],
);

/// Envía [n] frames iguales cada [paso] y devuelve la última evaluación.
EvaluacionFrame? _frames(MotorEjercicio m, Pose p, int n, Duration paso,
    {int desde = 0}) {
  EvaluacionFrame? e;
  for (var i = desde; i < desde + n; i++) {
    e = m.evaluar(p, instante: _t0.add(paso * i));
  }
  return e;
}

void main() {
  group('Racha', () {
    test('necesita tiempo Y frames', () {
      final r = Racha();
      const min = Duration(milliseconds: 100);
      r.actualizar(true, _t0);
      expect(r.confirmada(_t0, minimo: min), isFalse); // 1 frame, 0 ms
      final t1 = _t0.add(const Duration(milliseconds: 120));
      r.actualizar(true, t1);
      expect(r.confirmada(t1, minimo: min), isTrue); // 2 frames, 120 ms
    });

    test('mucho tiempo con un solo frame no basta', () {
      final r = Racha()..actualizar(true, _t0);
      final tarde = _t0.add(const Duration(seconds: 1));
      expect(r.confirmada(tarde, minimo: Duration.zero), isFalse);
      expect(r.confirmada(tarde, minimo: Duration.zero, frames: 1), isTrue);
    });

    test('un frame que no cumple corta la racha', () {
      final r = Racha()
        ..actualizar(true, _t0)
        ..actualizar(true, _t0.add(const Duration(milliseconds: 50)))
        ..actualizar(false, _t0.add(const Duration(milliseconds: 100)));
      expect(r.frames, 0);
      expect(
          r.confirmada(_t0.add(const Duration(milliseconds: 100)),
              minimo: Duration.zero),
          isFalse);
    });
  });

  group('Errores instantáneos: mismo tiempo a cualquier FPS', () {
    test('framesMinimos = 3 equivale a 100 ms (y 300 ms si se indica)', () {
      final regla = _recetaPrueba.reglasForma;
      expect(regla[0].msMinimos, 100);
      expect(regla[1].msMinimos, 300);
    });

    test('10 FPS: el aviso sale a los 100 ms (antes tardaba 200 ms)', () {
      final m = MotorEjercicio(_recetaPrueba);
      const paso = Duration(milliseconds: 100);
      final e = _frames(m, _tabla(hundimiento: 30), 2, paso);
      expect(e!.erroresActivos.map((r) => r.id), ['cadera_caida']);
    });

    test('40 FPS: 3 frames (50 ms) aún no bastan; 5 frames (100 ms) sí', () {
      final m = MotorEjercicio(_recetaPrueba);
      const paso = Duration(milliseconds: 25);
      final p = _tabla(hundimiento: 30);
      expect(_frames(m, p, 3, paso)!.erroresActivos, isEmpty);
      final e = _frames(m, p, 2, paso, desde: 3);
      expect(e!.erroresActivos.map((r) => r.id), ['cadera_caida']);
    });

    test('regla con msMinimos = 300 espera más', () {
      final m = MotorEjercicio(_recetaPrueba);
      const paso = Duration(milliseconds: 50);
      final p = _tabla(hundimiento: 30);
      final antes = _frames(m, p, 6, paso)!; // 0..250 ms
      expect(antes.erroresActivos.map((r) => r.id), ['cadera_caida']);
      final despues = _frames(m, p, 1, paso, desde: 6)!; // 300 ms
      expect(despues.erroresActivos.map((r) => r.id),
          ['cadera_caida', 'lenta']);
    });
  });

  test('sentadilla real: 3 reps correctas a 10, 15, 20 y 30 FPS', () {
    for (final fps in [10, 15, 20, 30]) {
      final m = MotorEjercicio(recetaSentadilla);
      final paso = Duration(microseconds: (1e6 / fps).round());
      const periodo = 2.5; // s por sentadilla
      var reps = 0, correctas = 0;
      for (var i = 0; i * paso.inMicroseconds / 1e6 < periodo * 3 + 0.6; i++) {
        final t = i * paso.inMicroseconds / 1e6;
        final rodilla =
            t > periodo * 3 ? 175.0 : 132.5 + 42.5 * cos(2 * pi * t / periodo);
        final rep = m
            .evaluar(_sentadilla(rodilla), instante: _t0.add(paso * i))
            ?.repCompletada;
        if (rep != null) {
          reps++;
          if (rep.esCorrecta) correctas++;
        }
      }
      expect(reps, 3, reason: '$fps FPS');
      expect(correctas, 3, reason: '$fps FPS');
    }
  });
}