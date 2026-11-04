import 'package:corrector_postura/core/geometria.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Crea un punto de prueba (coordenadas de imagen: y crece hacia abajo).
PoseLandmark pt(double x, double y,
        [PoseLandmarkType tipo = PoseLandmarkType.nose]) =>
    PoseLandmark(type: tipo, x: x, y: y, z: 0, likelihood: 1);

void main() {
  group('calcularAngulo', () {
    test('ángulo recto = 90°', () {
      expect(calcularAngulo(pt(0, -100), pt(0, 0), pt(100, 0)),
          closeTo(90, 0.001));
    });

    test('segmento recto = 180°', () {
      expect(calcularAngulo(pt(0, -100), pt(0, 0), pt(0, 100)),
          closeTo(180, 0.001));
    });

    test('siempre devuelve entre 0° y 180°', () {
      final a = calcularAngulo(pt(100, 0), pt(0, 0), pt(-100, -1));
      expect(a, inInclusiveRange(0, 180));
    });
  });

  group('inclinacionRespectoVertical', () {
    test('torso erguido = 0°', () {
      expect(inclinacionRespectoVertical(pt(0, 0), pt(0, 100)),
          closeTo(0, 0.001));
    });

    test('torso a 45° (hacia cualquier lado) = 45°', () {
      expect(inclinacionRespectoVertical(pt(100, 0), pt(0, 100)),
          closeTo(45, 0.001));
      expect(inclinacionRespectoVertical(pt(-100, 0), pt(0, 100)),
          closeTo(45, 0.001));
    });

    test('cuerpo horizontal = 90°', () {
      expect(inclinacionRespectoVertical(pt(100, 100), pt(0, 100)),
          closeTo(90, 0.001));
    });
  });

  group('inclinacionRespectoHorizontal', () {
    test('acostado = 0°, de pie = 90°', () {
      expect(inclinacionRespectoHorizontal(pt(0, 0), pt(300, 0)),
          closeTo(0, 0.001));
      expect(inclinacionRespectoHorizontal(pt(0, 0), pt(0, 300)),
          closeTo(90, 0.001));
    });
  });

  group('desviacionDeLinea', () {
    // Recta hombro (0,300) -> tobillo (300,300), largo 300.
    final hombro = pt(0, 300), tobillo = pt(300, 300);

    test('cadera alineada = 0', () {
      expect(desviacionDeLinea(hombro, tobillo, pt(150, 300)),
          closeTo(0, 0.001));
    });

    test('cadera POR DEBAJO (caída) = positivo', () {
      // 30 px más abajo / 300 de largo = 0.1
      expect(desviacionDeLinea(hombro, tobillo, pt(150, 330)),
          closeTo(0.1, 0.001));
    });

    test('cadera POR ENCIMA (elevada) = negativo', () {
      expect(desviacionDeLinea(hombro, tobillo, pt(150, 270)),
          closeTo(-0.1, 0.001));
    });

    test('recta vertical = null', () {
      expect(desviacionDeLinea(pt(0, 0), pt(0, 300), pt(10, 150)), isNull);
    });
  });

  group('espejo', () {
    test('cambia de lado y deja igual las centrales', () {
      expect(espejo(PoseLandmarkType.rightKnee), PoseLandmarkType.leftKnee);
      expect(espejo(PoseLandmarkType.leftShoulder),
          PoseLandmarkType.rightShoulder);
      expect(espejo(PoseLandmarkType.nose), PoseLandmarkType.nose);
    });
  });
}
