import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'receta_ejercicio.dart';

/// Receta de la sentadilla. Usa el ángulo cadera-rodilla-tobillo del lado
/// derecho para contar repeticiones.
final recetaSentadilla = RecetaEjercicio(
  id: 'squat',
  nombre: 'Sentadilla',
  tipo: TipoEjercicio.dinamico,
  deteccionRepeticion: const DeteccionRepeticion(
    articulacionA: PoseLandmarkType.rightHip,
    articulacionB: PoseLandmarkType.rightKnee,
    articulacionC: PoseLandmarkType.rightAnkle,
    umbralAbajo: 100,
    umbralArriba: 150,
  ),
  reglasForma: [
    // 1) Profundidad insuficiente: en el punto más bajo no dobla suficiente.
    ReglaForma(
      id: 'profundidad_insuficiente',
      mensaje: 'Baja más, no alcanzas la profundidad',
      severidad: Severidad.media,
      condicion: (ctx) => ctx.anguloPrincipal > 120,
    ),
    // 2) Espalda muy inclinada: ángulo del tronco (hombro-cadera-rodilla) pequeño.
    ReglaForma(
      id: 'espalda_curva',
      mensaje: 'Mantén la espalda más recta',
      severidad: Severidad.alta,
      condicion: (ctx) {
        final t = ctx.angulo(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
        );
        return t != null && t < 45;
      },
    ),
  ],
);