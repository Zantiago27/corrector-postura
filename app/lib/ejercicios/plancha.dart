import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'receta_ejercicio.dart';

/// Receta de la plancha (isométrica): no cuenta repeticiones,
/// mide el tiempo que aguantas el cuerpo recto.
final recetaPlancha = RecetaEjercicio(
  id: 'plank',
  nombre: 'Plancha',
  tipo: TipoEjercicio.isometrico,
  // Sin deteccionRepeticion: en un isométrico no se cuentan reps.
  reglasForma: [
    // El cuerpo debe formar una línea recta hombro-cadera-tobillo (~180°).
    // Si la cadera se cae o se eleva, el ángulo baja de 160°.
    ReglaForma(
      id: 'cuerpo_no_recto',
      mensaje: 'Mantén el cuerpo recto, cadera en línea',
      severidad: Severidad.alta,
      condicion: (ctx) {
        final a = ctx.angulo(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightAnkle,
        );
        return a != null && a < 160;
      },
    ),
  ],
);