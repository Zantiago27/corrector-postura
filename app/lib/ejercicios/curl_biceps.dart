import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'receta_ejercicio.dart';

/// Receta del curl de bíceps (brazo derecho).
/// Ángulo hombro-codo-muñeca: brazo estirado ~170°, flexionado ~40°.
final recetaCurl = RecetaEjercicio(
  id: 'curl',
  nombre: 'Curl de bíceps',
  tipo: TipoEjercicio.dinamico,
  deteccionRepeticion: const DeteccionRepeticion(
    articulacionA: PoseLandmarkType.rightShoulder,
    articulacionB: PoseLandmarkType.rightElbow,
    articulacionC: PoseLandmarkType.rightWrist,
    umbralAbajo: 60,    // ángulo pequeño = brazo flexionado (curl completo)
    umbralArriba: 150,  // ángulo grande = brazo estirado (posición inicial)
  ),
  reglasForma: [
    // El codo debe quedarse pegado al costado. Si el brazo se balancea
    // hacia adelante (usar impulso), el ángulo codo-hombro-cadera crece.
    ReglaForma(
      id: 'codo_separado',
      mensaje: 'Pega el codo al cuerpo, no uses impulso',
      severidad: Severidad.alta,
      condicion: (ctx) {
        final a = ctx.angulo(
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
        );
        return a != null && a > 40;
      },
    ),
  ],
);