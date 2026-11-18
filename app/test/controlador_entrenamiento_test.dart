import 'package:corrector_postura/core/controlador_entrenamiento.dart';
import 'package:corrector_postura/ejercicios/sentadilla.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// ---------------------------------------------------------------------------
// Flujo manos libres (Fase D): auto-inicio 3-2-1, cancelación, botón,
// pausa automática y duración sin pausas. Sin cámara: reloj simulado.
// ---------------------------------------------------------------------------

/// Persona de pie, de perfil (lado derecho), bien visible.
Pose _poseDePie() => Pose(landmarks: {
      for (final (tipo, x, y) in [
        (PoseLandmarkType.rightShoulder, 300.0, 100.0),
        (PoseLandmarkType.rightHip, 300.0, 250.0),
        (PoseLandmarkType.rightKnee, 300.0, 330.0),
        (PoseLandmarkType.rightAnkle, 300.0, 400.0),
      ])
        tipo: PoseLandmark(type: tipo, x: x, y: y, z: 0, likelihood: 0.99),
    });

/// Sesión con reloj simulado: un frame cada 50 ms (20 FPS).
class _Sesion {
  static const paso = Duration(milliseconds: 50);

  DateTime reloj = DateTime(2026, 1, 1);
  late final ControladorEntrenamiento c =
      ControladorEntrenamiento(recetaSentadilla, ahora: reloj);
  final List<String> anuncios = [];
  final Pose pie = _poseDePie();

  /// Envía frames durante [duracion]. [pose] null = nadie a la vista.
  void durante(Duration duracion, Pose? pose) {
    final fin = reloj.add(duracion);
    while (reloj.isBefore(fin)) {
      final anuncio = c.procesar(pose, reloj);
      if (anuncio != null) anuncios.add(anuncio.texto);
      reloj = reloj.add(paso);
    }
  }

  /// Encuadrado 2 s + cuenta 3-2-1 → entrenando.
  void hastaEntrenar() {
    durante(const Duration(milliseconds: 2100), pie);
    durante(const Duration(milliseconds: 3100), pie);
  }
}

void main() {
  group('Preparación y cuenta regresiva', () {
    test('sin nadie en cuadro se queda en "preparando"', () {
      final s = _Sesion()..durante(const Duration(seconds: 5), null);
      expect(s.c.estado, EstadoSesion.preparando);
      expect(s.c.encuadreOk, isFalse);
      expect(s.anuncios, isEmpty);
    });

    test('encuadrado 2 s → arranca la cuenta y dice "3"', () {
      final s = _Sesion()..durante(const Duration(milliseconds: 1900), _poseDePie());
      expect(s.c.estado, EstadoSesion.preparando);
      expect(s.c.progresoAutoInicio(s.reloj), greaterThan(0.9));

      s.durante(const Duration(milliseconds: 300), s.pie);
      expect(s.c.estado, EstadoSesion.cuentaRegresiva);
      expect(s.anuncios.last, '3');
      expect(s.c.numeroCuenta(s.reloj), 3);
    });

    test('cuenta 3-2-1 y "¡Vamos!" → entrenando', () {
      final s = _Sesion()..hastaEntrenar();
      expect(s.c.estado, EstadoSesion.entrenando);
      expect(s.anuncios.take(4).toList(), ['3', '2', '1', '¡Vamos!']);
    });

    test('salir de cuadro más de 0.7 s cancela la cuenta', () {
      final s = _Sesion()..durante(const Duration(milliseconds: 2100), _poseDePie());
      expect(s.c.estado, EstadoSesion.cuentaRegresiva);
      s.durante(const Duration(milliseconds: 800), null);
      expect(s.c.estado, EstadoSesion.preparando);
      expect(s.anuncios.last, 'Vuelve a colocarte');
    });

    test('un parpadeo corto (< 0.7 s) no cancela la cuenta', () {
      final s = _Sesion()..durante(const Duration(milliseconds: 2100), _poseDePie());
      s.durante(const Duration(milliseconds: 300), null);
      s.durante(const Duration(milliseconds: 200), s.pie);
      expect(s.c.estado, EstadoSesion.cuentaRegresiva);
    });

    test('botón "Empezar": no sin encuadre; sí con encuadre (sin cuenta)', () {
      final s = _Sesion();
      expect(s.c.empezar(s.reloj), isFalse);
      s.durante(const Duration(milliseconds: 100), s.pie);
      expect(s.c.empezar(s.reloj), isTrue);
      expect(s.c.estado, EstadoSesion.entrenando);
      expect(s.c.empezar(s.reloj), isFalse); // ya está entrenando
    });
  });

  group('Pausa automática', () {
    test('fuera de cuadro 3 s → pausa (antes no)', () {
      final s = _Sesion()..hastaEntrenar();
      s.durante(const Duration(milliseconds: 2900), null);
      expect(s.c.estado, EstadoSesion.entrenando);
      s.durante(const Duration(milliseconds: 300), null);
      expect(s.c.estado, EstadoSesion.pausado);
      expect(s.anuncios, contains('Pausa. Vuelve al cuadro para seguir'));
    });

    test('al volver al cuadro dice "¡Seguimos!"', () {
      final s = _Sesion()..hastaEntrenar();
      s.durante(const Duration(milliseconds: 3200), null);
      s.durante(const Duration(milliseconds: 100), s.pie);
      expect(s.c.estado, EstadoSesion.entrenando);
      expect(s.anuncios, contains('¡Seguimos!'));
    });

    test('la duración guardada no cuenta el tiempo en pausa', () {
      final s = _Sesion()..hastaEntrenar(); // empieza a entrenar en t=5.0 s
      s.durante(const Duration(milliseconds: 800), s.pie); // hasta t=6.0 s
      s.durante(const Duration(seconds: 5), null); // fuera de t=6 a t=11 (pausa)
      s.durante(const Duration(seconds: 4), s.pie); // hasta t=15 s
      // 10 s desde el inicio − 5 s fuera de cuadro = 5 s.
      expect(s.c.duracionSegundos(s.reloj), 5);
    });

    test('mientras dura la pausa, la duración no avanza', () {
      final s = _Sesion()..hastaEntrenar();
      s.durante(const Duration(seconds: 4), null);
      expect(s.c.pausado, isTrue);
      final ahora = s.c.duracionSegundos(s.reloj);
      final despues =
          s.c.duracionSegundos(s.reloj.add(const Duration(seconds: 10)));
      expect(despues, ahora);
    });
  });
}