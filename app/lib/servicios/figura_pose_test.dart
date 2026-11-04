import 'dart:ui' show Offset;

import 'package:corrector_postura/core/motor_ejercicio.dart';
import 'package:corrector_postura/ejercicios/curl_biceps.dart';
import 'package:corrector_postura/ejercicios/figura_pose.dart';
import 'package:corrector_postura/ejercicios/instrucciones_ejercicio.dart';
import 'package:corrector_postura/ejercicios/plancha.dart';
import 'package:corrector_postura/ejercicios/sentadilla.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = FiguraPose.perfil(
    cabeza: const Offset(0, 0),
    hombro: const Offset(0, 0.2),
    codo: const Offset(0, 0.4),
    mano: const Offset(0, 0.6),
    cadera: const Offset(0, 0.5),
    rodilla: const Offset(0, 0.7),
    pie: const Offset(0, 0.9),
  );
  final b = FiguraPose.perfil(
    cabeza: const Offset(1, 0),
    hombro: const Offset(1, 0.2),
    codo: const Offset(1, 0.4),
    mano: const Offset(1, 0.6),
    cadera: const Offset(1, 0.5),
    rodilla: const Offset(1, 0.7),
    pie: const Offset(1, 0.9),
  );

  test('perfil: los dos lados coinciden', () {
    expect(a[ParteFigura.rodillaI], a[ParteFigura.rodillaD]);
  });

  test('lerp a mitad de camino', () {
    final m = FiguraPose.lerp(a, b, 0.5);
    expect(m[ParteFigura.caderaD], const Offset(0.5, 0.5));
    expect(FiguraPose.lerp(a, b, 0)[ParteFigura.pieI], a[ParteFigura.pieI]);
  });

  test('cada ejercicio tiene guía completa y poses dentro de la caja', () {
    for (final receta in [recetaSentadilla, recetaCurl, recetaPlancha]) {
      final guia = guiaDe(receta.id);
      expect(guia.colocacion, isNotEmpty, reason: receta.id);
      expect(guia.pasos, isNotEmpty, reason: receta.id);
      expect(guia.posesClave, isNotEmpty, reason: receta.id);
      for (final pose in guia.posesClave) {
        for (final o in pose.partes.values) {
          expect(o.dx, inInclusiveRange(0, 1), reason: receta.id);
          expect(o.dy, inInclusiveRange(0, 1), reason: receta.id);
        }
      }
      // El tutorial genera "Qué te voy a corregir" desde las reglas.
      for (final ReglaForma r in receta.reglasForma) {
        expect(r.mensajeLargo, isNotEmpty, reason: r.id);
      }
    }
  });
}