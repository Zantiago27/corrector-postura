import 'dart:math';

import 'package:corrector_postura/core/coach_entrenamiento.dart';
import 'package:corrector_postura/core/controlador_entrenamiento.dart';
import 'package:corrector_postura/ejercicios/sentadilla.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pose de perfil (lado derecho) con la rodilla en [angulo] grados.
Pose poseSentadilla(double angulo) {
  final t = angulo * pi / 180;
  const kx = 300.0, ky = 400.0;
  final hx = kx + 100 * sin(t), hy = ky + 100 * cos(t);
  PoseLandmark lm(PoseLandmarkType tipo, double x, double y) =>
      PoseLandmark(type: tipo, x: x, y: y, z: 0, likelihood: 0.99);
  final puntos = [
    lm(PoseLandmarkType.rightShoulder, hx + 17, hy - 98), // torso ~10°
    lm(PoseLandmarkType.rightHip, hx, hy),
    lm(PoseLandmarkType.rightKnee, kx, ky),
    lm(PoseLandmarkType.rightAnkle, kx, ky + 100),
  ];
  return Pose(landmarks: {for (final p in puntos) p.type: p});
}

final dePie = poseSentadilla(175);

void main() {
  late ControladorEntrenamiento ctrl;
  late DateTime reloj;
  const paso = Duration(milliseconds: 50);

  /// Procesa un frame y devuelve el anuncio (si lo hay).
  Anuncio? frame(Pose? pose) {
    final a = ctrl.procesar(pose, reloj);
    reloj = reloj.add(paso);
    return a;
  }

  /// Repite un frame durante [d] y devuelve los textos anunciados.
  List<String> durante(Duration d, Pose? pose) {
    final textos = <String>[];
    final fin = reloj.add(d);
    while (reloj.isBefore(fin)) {
      final a = frame(pose);
      if (a != null) textos.add(a.texto);
    }
    return textos;
  }

  /// Una sentadilla completa; devuelve todos los anuncios que produjo.
  List<String> sentadilla() {
    final textos = <String>[];
    void f(double a) {
      final x = frame(poseSentadilla(a));
      if (x != null) textos.add(x.texto);
    }

    for (var a = 175.0; a > 90; a -= 5) {
      f(a);
    }
    for (var i = 0; i < 4; i++) {
      f(90);
    }
    for (var a = 90.0; a < 175; a += 5) {
      f(a);
    }
    for (var i = 0; i < 6; i++) {
      f(175);
    }
    return textos;
  }

  /// Atajo: encuadrar y empezar con el botón.
  void empezarConBoton() {
    frame(dePie);
    expect(ctrl.empezar(reloj), isTrue);
  }

  setUp(() {
    reloj = DateTime(2026, 1, 1);
    ctrl = ControladorEntrenamiento(recetaSentadilla, ahora: reloj);
  });

  group('Inicio manos libres', () {
    test('encuadrado 2 s -> cuenta 3, 2, 1 -> "¡Vamos!" y entrena', () {
      expect(durante(const Duration(milliseconds: 1900), dePie), isEmpty);
      expect(ctrl.estado, EstadoSesion.preparando);
      final textos = durante(const Duration(milliseconds: 3300), dePie);
      expect(textos, ['3', '2', '1', '¡Vamos!']);
      expect(ctrl.estado, EstadoSesion.entrenando);
    });

    test('si sales de cuadro en la cuenta, se cancela', () {
      durante(const Duration(milliseconds: 2100), dePie);
      expect(ctrl.enCuentaRegresiva, isTrue);
      final textos = durante(const Duration(seconds: 1), null);
      expect(textos, contains('Vuelve a colocarte'));
      expect(ctrl.estado, EstadoSesion.preparando);
    });

    test('un frame perdido NO cancela la cuenta', () {
      durante(const Duration(milliseconds: 2100), dePie);
      frame(null);
      durante(const Duration(milliseconds: 300), dePie);
      expect(ctrl.enCuentaRegresiva, isTrue);
    });

    test('progreso del auto-inicio va de 0 a 1', () {
      frame(dePie);
      expect(ctrl.progresoAutoInicio(reloj), closeTo(0.025, 0.03));
      durante(const Duration(seconds: 1), dePie);
      expect(ctrl.progresoAutoInicio(reloj), closeTo(0.5, 0.06));
    });

    test('botón Empezar: arranca ya, sin cuenta regresiva', () {
      empezarConBoton();
      expect(ctrl.estado, EstadoSesion.entrenando);
    });

    test('no se puede empezar sin encuadre', () {
      expect(ctrl.empezar(reloj), isFalse);
      expect(ctrl.entrenando, isFalse);
    });

    test('antes de entrenar no se cuentan reps', () {
      sentadilla();
      expect(ctrl.repsTotales, 0);
    });
  });

  group('Entrenando', () {
    test('una sentadilla buena = rep guardada y voz "1"', () {
      empezarConBoton();
      final textos = sentadilla();
      expect(ctrl.repsCorrectas, 1);
      expect(ctrl.reps, hasLength(1));
      expect(textos, contains('1'));
      expect(ctrl.coach.veredictos, [true]);
    });

    test('reiniciar serie deja todo en cero', () {
      empezarConBoton();
      sentadilla();
      ctrl.reiniciarSerie(reloj);
      expect(ctrl.repsTotales, 0);
      expect(ctrl.reps, isEmpty);
      expect(ctrl.coach.veredictos, isEmpty);
      expect(ctrl.entrenando, isTrue);
    });
  });

  group('Pausa automática', () {
    test('fuera de cuadro 3 s -> pausa; al volver -> "¡Seguimos!"', () {
      empezarConBoton();
      final alSalir = durante(const Duration(milliseconds: 3200), null);
      expect(alSalir, contains('Pausa. Vuelve al cuadro para seguir'));
      expect(ctrl.pausado, isTrue);

      expect(frame(dePie)?.texto, '¡Seguimos!');
      expect(ctrl.estado, EstadoSesion.entrenando);
    });

    test('salir de cuadro menos de 3 s NO pausa', () {
      empezarConBoton();
      durante(const Duration(seconds: 2), null);
      frame(dePie);
      expect(ctrl.pausado, isFalse);
    });

    test('la duración no cuenta el tiempo en pausa', () {
      empezarConBoton();
      final inicio = reloj;
      durante(const Duration(seconds: 10), dePie); // 10 s entrenando
      durante(const Duration(seconds: 20), null); // 20 s fuera (pausa)
      frame(dePie);
      final total = ctrl.duracionSegundos(reloj);
      expect(reloj.difference(inicio).inSeconds, greaterThanOrEqualTo(30));
      expect(total, inInclusiveRange(9, 11));
    });
  });
}