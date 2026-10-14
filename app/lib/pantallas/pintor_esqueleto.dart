import 'package:camera/camera.dart';
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

  PintorEsqueleto({
    required this.poses,
    required this.tamanoImagen,
    required this.rotacion,
    required this.lente,
    this.formaCorrecta = true,
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
    final pintorPunto = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    final pintorPuntoBorde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colorLinea;

    for (final pose in poses) {
      // Une dos articulaciones con una línea.
      void unir(PoseLandmarkType a, PoseLandmarkType b) {
        final pa = pose.landmarks[a];
        final pb = pose.landmarks[b];
        if (pa == null || pb == null) return;
        canvas.drawLine(
          Offset(_traducirX(pa.x, size), _traducirY(pa.y, size)),
          Offset(_traducirX(pb.x, size), _traducirY(pb.y, size)),
          pintorHueso,
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

      // Puntos encima de las líneas (círculo blanco con borde de color).
      pose.landmarks.forEach((_, punto) {
        final centro =
            Offset(_traducirX(punto.x, size), _traducirY(punto.y, size));
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
      anterior.poses != poses || anterior.formaCorrecta != formaCorrecta;
}