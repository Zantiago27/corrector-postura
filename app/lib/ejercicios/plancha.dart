import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'receta_ejercicio.dart';

/// Receta de la plancha (isométrica, vista LATERAL).
/// No cuenta repeticiones: mide el tiempo que aguantas con el cuerpo recto.
///
/// Antes había una sola regla ("cuerpo_no_recto") que no distinguía si la
/// cadera se caía o subía, así que el usuario no sabía qué corregir.
/// Ahora se mide la desviación de la cadera respecto a la recta
/// hombro-tobillo, CON SIGNO, y cada caso tiene su propio mensaje.
final recetaPlancha = RecetaEjercicio(
  id: 'plank',
  nombre: 'Plancha',
  tipo: TipoEjercicio.isometrico,
  vista: VistaCamara.lateral,
  orientacion: OrientacionSugerida.horizontal,
  ladoAutomatico: true,
  puntosRequeridos: const [
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
  ],
  // Solo cuenta el tiempo si el cuerpo está casi horizontal
  // (así no avanza el cronómetro si estás de pie).
  posicionValida: (ctx) {
    final inclinacion = ctx.inclinacionHorizontal(
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightAnkle,
    );
    return inclinacion != null && inclinacion < 35;
  },
  mensajePosicion: 'Colócate en posición de plancha',
  reglasForma: [
    // 1) Cadera caída: lo más importante (carga la zona lumbar).
    ReglaForma.instantanea(
      id: 'cadera_caida',
      mensajeCorto: 'Sube la cadera',
      mensajeLargo: 'Tu cadera se está cayendo. Aprieta el abdomen y los '
          'glúteos para formar una línea recta de hombros a tobillos.',
      severidad: Severidad.alta,
      framesMinimos: 4,
      articulaciones: const [PoseLandmarkType.rightHip],
      condicion: (ctx) {
        final d = ctx.desviacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightAnkle,
          PoseLandmarkType.rightHip,
        );
        return d != null && d > 0.06;
      },
    ),
    // 2) Cadera demasiado alta: le quita trabajo al abdomen.
    ReglaForma.instantanea(
      id: 'cadera_elevada',
      mensajeCorto: 'Baja la cadera',
      mensajeLargo: 'Tu cadera está muy alta. Bájala hasta que hombros, '
          'cadera y tobillos queden alineados.',
      severidad: Severidad.media,
      framesMinimos: 4,
      articulaciones: const [PoseLandmarkType.rightHip],
      condicion: (ctx) {
        final d = ctx.desviacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightAnkle,
          PoseLandmarkType.rightHip,
        );
        return d != null && d < -0.08;
      },
    ),
  ],
);