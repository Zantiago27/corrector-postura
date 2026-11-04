import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../config/tema.dart';

/// Dibuja el esqueleto (puntos + líneas) sobre el preview de la cámara.
/// Traduce las coordenadas de ML Kit al tamaño real en pantalla, teniendo
/// en cuenta la rotación y el espejado de la cámara frontal.
class PintorEsqueleto extends CustomPainter {
  final List<Pose> poses;
  final Size tamanoImagen;
  final InputImageRotation rotacion;
  final CameraLensDirection lente;

  /// Color de las líneas según el estado de la forma (verde = correcta).
  final bool formaCorrecta;

  /// Articulaciones donde está el error ahora mismo (Fase C): se dibujan
  /// con un halo para que el usuario vea QUÉ parte corregir.
  final Set<PoseLandmarkType> articulacionesResaltadas;

  PintorEsqueleto({
    required this.poses,
    required this.tamanoImagen,
    required this.rotacion,
    required this.lente,
    this.formaCorrecta = true,
    this.articulacionesResaltadas = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty || tamanoImagen == Size.zero) return;

    final colorLinea = formaCorrecta ? Colores.ok : Colores.acento;

    final pintorHueso = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = colorLinea;
    final pintorHuesoResaltado = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Colores.acento;
    final pintorPunto = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    final pintorPuntoBorde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colorLinea;
    final pintorHalo = Paint()
      ..style = PaintingStyle.fill
      ..color = Colores.acento.withValues(alpha: 0.45);
    final pintorHaloBorde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;

    for (final pose in poses) {
      Offset aPantalla(PoseLandmark p) =>
          Offset(_traducirX(p.x, size), _traducirY(p.y, size));

      // Une dos articulaciones con una línea. Si ambas tienen error, el
      // hueso se dibuja más grueso y en naranja.
      void unir(PoseLandmarkType a, PoseLandmarkType b) {
        final pa = pose.landmarks[a];
        final pb = pose.landmarks[b];
        if (pa == null || pb == null) return;
        final resaltado = articulacionesResaltadas.contains(a) &&
            articulacionesResaltadas.contains(b);
        canvas.drawLine(
          aPantalla(pa),
          aPantalla(pb),
          resaltado ? pintorHuesoResaltado : pintorHueso,
        );
      }

      // Brazos
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      unir(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      unir(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      unir(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
      // Piernas
      unir(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      unir(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      unir(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      unir(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
      // Tronco
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      unir(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      unir(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);

      // Halo en las articulaciones con error (debajo del punto).
      for (final tipo in articulacionesResaltadas) {
        final p = pose.landmarks[tipo];
        if (p == null) continue;
        final centro = aPantalla(p);
        canvas.drawCircle(centro, 16, pintorHalo);
        canvas.drawCircle(centro, 16, pintorHaloBorde);
      }

      // Puntos encima de las líneas (círculo blanco con borde de color).
      pose.landmarks.forEach((_, punto) {
        final centro = aPantalla(punto);
        canvas.drawCircle(centro, 5, pintorPunto);
        canvas.drawCircle(centro, 5, pintorPuntoBorde);
      });
    }
  }

  // Convierte la coordenada X de la imagen a la X en pantalla.
  double _traducirX(double x, Size canvas) {
    switch (rotacion) {
      case InputImageRotation.rotation90deg:
        return x * canvas.width / tamanoImagen.height;
      case InputImageRotation.rotation270deg:
        return canvas.width - x * canvas.width / tamanoImagen.height;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        if (lente == CameraLensDirection.back) {
          return x * canvas.width / tamanoImagen.width;
        }
        return canvas.width - x * canvas.width / tamanoImagen.width;
    }
  }

  // Convierte la coordenada Y de la imagen a la Y en pantalla.
  double _traducirY(double y, Size canvas) {
    switch (rotacion) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvas.height / tamanoImagen.width;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvas.height / tamanoImagen.height;
    }
  }

  @override
  bool shouldRepaint(covariant PintorEsqueleto anterior) =>
      anterior.poses != poses ||
      anterior.formaCorrecta != formaCorrecta ||
      !setEquals(anterior.articulacionesResaltadas, articulacionesResaltadas);
}
