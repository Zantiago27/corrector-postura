// lib/pantallas/silueta_puntos.dart
//
// Ilustración del "esqueleto de puntos" del boceto (detección de pose),
// dibujada con CustomPaint. Reutilizable: onboarding, tarjetas, etc.
// Replica las coordenadas del SVG original (viewBox 220 x 380) y las escala
// al tamaño que se le dé.

import 'package:flutter/material.dart';

import '../config/tema.dart';

class SiluetaPuntos extends StatelessWidget {
  final double size;
  const SiluetaPuntos({super.key, this.size = 150});

  @override
  Widget build(BuildContext context) {
    // Mantiene la proporción original 220:380.
    return SizedBox(
      width: size,
      height: size * 380 / 220,
      child: CustomPaint(painter: _PintorSilueta()),
    );
  }
}

class _PintorSilueta extends CustomPainter {
  // Puntos del esqueleto en coordenadas del viewBox original (220 x 380).
  static const _cabeza = Offset(110, 70);
  static const _cuello = Offset(110, 80);
  static const _torsoSup = Offset(110, 100);
  static const _hombroIzq = Offset(82, 112);
  static const _hombroDer = Offset(138, 112);
  static const _codoIzq = Offset(70, 158);
  static const _codoDer = Offset(150, 158);
  static const _manoIzq = Offset(80, 196);
  static const _manoDer = Offset(140, 196);
  static const _torsoInf = Offset(110, 188);
  static const _caderaIzq = Offset(90, 190);
  static const _caderaDer = Offset(130, 190);
  static const _rodillaIzq = Offset(78, 258);
  static const _rodillaDer = Offset(142, 258);
  static const _pieIzq = Offset(88, 326);
  static const _pieDer = Offset(132, 326);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 220.0;
    final sy = size.height / 380.0;
    Offset p(Offset o) => Offset(o.dx * sx, o.dy * sy);

    final lineas = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * sx
      ..strokeCap = StrokeCap.round
      ..color = Colores.acento;

    // Huesos
    final conexiones = <List<Offset>>[
      [_cuello, _torsoSup],
      [_torsoSup, _hombroIzq],
      [_torsoSup, _hombroDer],
      [_hombroIzq, _codoIzq],
      [_codoIzq, _manoIzq],
      [_hombroDer, _codoDer],
      [_codoDer, _manoDer],
      [_torsoSup, _torsoInf],
      [_torsoInf, _caderaIzq],
      [_torsoInf, _caderaDer],
      [_caderaIzq, _rodillaIzq],
      [_rodillaIzq, _pieIzq],
      [_caderaDer, _rodillaDer],
      [_rodillaDer, _pieDer],
    ];
    for (final c in conexiones) {
      canvas.drawLine(p(c[0]), p(c[1]), lineas);
    }

    // Articulaciones (puntos oscuros)
    final puntoPeq = Paint()
      ..style = PaintingStyle.fill
      ..color = Colores.sobreAcento;
    final articulaciones = [
      _hombroIzq, _hombroDer, _codoIzq, _codoDer,
      _caderaIzq, _caderaDer, _rodillaIzq, _rodillaDer,
      _pieIzq, _pieDer,
    ];
    for (final a in articulaciones) {
      canvas.drawCircle(p(a), 5 * sx, puntoPeq);
    }

    // Cabeza (círculo de acento)
    final cabeza = Paint()
      ..style = PaintingStyle.fill
      ..color = Colores.acento;
    canvas.drawCircle(p(_cabeza), 13 * sx, cabeza);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}