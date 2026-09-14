import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Dibuja el esqueleto (puntos + líneas) sobre el preview de la cámara.
/// Traduce las coordenadas de ML Kit al tamaño real en pantalla, teniendo
/// en cuenta la rotación y el espejado de la cámara frontal.
class PintorEsqueleto extends CustomPainter {
  final List<Pose> poses;
  final Size tamanoImagen;
  final InputImageRotation rotacion;
  final CameraLensDirection lente;

  PintorEsqueleto({
    required this.poses,
    required this.tamanoImagen,
    required this.rotacion,
    required this.lente,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty || tamanoImagen == Size.zero) return;

    final pintorPunto = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.tealAccent;
    final pintorIzq = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.lightGreenAccent;
    final pintorDer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.orangeAccent;
    final pintorTronco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white;

    for (final pose in poses) {
      // Un círculo por cada punto detectado.
      pose.landmarks.forEach((_, punto) {
        canvas.drawCircle(
          Offset(_traducirX(punto.x, size), _traducirY(punto.y, size)),
          5,
          pintorPunto,
        );
      });

      // Une dos articulaciones con una línea.
      void unir(PoseLandmarkType a, PoseLandmarkType b, Paint pintor) {
        final pa = pose.landmarks[a];
        final pb = pose.landmarks[b];
        if (pa == null || pb == null) return;
        canvas.drawLine(
          Offset(_traducirX(pa.x, size), _traducirY(pa.y, size)),
          Offset(_traducirX(pb.x, size), _traducirY(pb.y, size)),
          pintor,
        );
      }

      // Brazos
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, pintorIzq);
      unir(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, pintorIzq);
      unir(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, pintorDer);
      unir(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, pintorDer);
      // Piernas
      unir(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, pintorIzq);
      unir(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, pintorIzq);
      unir(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, pintorDer);
      unir(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, pintorDer);
      // Tronco
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, pintorTronco);
      unir(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, pintorTronco);
      unir(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, pintorTronco);
      unir(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, pintorTronco);
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
      anterior.poses != poses;
}