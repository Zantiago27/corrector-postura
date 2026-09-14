import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Resultado de procesar un frame: las poses detectadas y los datos
/// necesarios para dibujarlas correctamente en pantalla.
class ResultadoPose {
  final List<Pose> poses;
  final Size tamanoImagen;            // tamaño del buffer crudo (sin rotar)
  final InputImageRotation rotacion;

  ResultadoPose(this.poses, this.tamanoImagen, this.rotacion);

  static ResultadoPose vacio() =>
      ResultadoPose([], Size.zero, InputImageRotation.rotation0deg);
}

/// Envuelve toda la lógica de ML Kit Pose: recibe un frame de la cámara,
/// lo traduce al formato de ML Kit y devuelve las poses (con sus 33 puntos).
class DetectorPose {
  final PoseDetector _detector = PoseDetector(options: PoseDetectorOptions());

  final _orientaciones = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<ResultadoPose> procesarFrame({
    required CameraImage imagen,
    required CameraController controlador,
    required CameraDescription camara,
  }) async {
    final inputImage = _convertir(imagen, controlador, camara);
    if (inputImage == null || inputImage.metadata == null) {
      return ResultadoPose.vacio();
    }
    final poses = await _detector.processImage(inputImage);
    return ResultadoPose(
      poses,
      inputImage.metadata!.size,
      inputImage.metadata!.rotation,
    );
  }

  /// Traduce el CameraImage crudo a un InputImage para ML Kit.
  InputImage? _convertir(
    CameraImage imagen,
    CameraController controlador,
    CameraDescription camara,
  ) {
    final sensorOrientation = camara.sensorOrientation;
    InputImageRotation? rotacion;

    if (Platform.isAndroid) {
      var compensacion = _orientaciones[controlador.value.deviceOrientation];
      if (compensacion == null) return null;
      if (camara.lensDirection == CameraLensDirection.front) {
        compensacion = (sensorOrientation + compensacion) % 360;
      } else {
        compensacion = (sensorOrientation - compensacion + 360) % 360;
      }
      rotacion = InputImageRotationValue.fromRawValue(compensacion);
    } else {
      rotacion = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotacion == null) return null;

    final formato = InputImageFormatValue.fromRawValue(imagen.format.raw);
    if (formato == null) return null;

    if (imagen.planes.length != 1) return null;
    final plano = imagen.planes.first;

    return InputImage.fromBytes(
      bytes: plano.bytes,
      metadata: InputImageMetadata(
        size: Size(imagen.width.toDouble(), imagen.height.toDouble()),
        rotation: rotacion,
        format: formato,
        bytesPerRow: plano.bytesPerRow,
      ),
    );
  }

  Future<void> cerrar() => _detector.close();
}