import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'receta_ejercicio.dart';

/// Receta de la sentadilla (vista LATERAL).
///
/// Conteo: ángulo de la rodilla (cadera-rodilla-tobillo).
///   - De pie:            ~170°  (reposo si > 160°)
///   - Intento de bajada: < 120° (extremo)
///   - Profundidad buena: <= 100° (muslo casi paralelo al suelo)
///
/// Nota de diseño: el umbral de extremo (120°) es MÁS ALTO que la
/// profundidad buena (100°) a propósito. Así una sentadilla corta SÍ se
/// cuenta, pero como "a corregir" con el aviso "Baja más". Si ambos
/// umbrales fueran iguales, la sentadilla corta simplemente no contaría
/// y el usuario no sabría por qué.
///
/// Los umbrales son valores iniciales: se calibran en la Fase H con
/// grabaciones reales.
final recetaSentadilla = RecetaEjercicio(
  id: 'squat',
  nombre: 'Sentadilla',
  tipo: TipoEjercicio.dinamico,
  vista: VistaCamara.lateral,
  orientacion: OrientacionSugerida.vertical,
  ladoAutomatico: true,
  puntosRequeridos: const [
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
  ],
  deteccionRepeticion: DeteccionRepeticion.angulo(
    a: PoseLandmarkType.rightHip,
    b: PoseLandmarkType.rightKnee,
    c: PoseLandmarkType.rightAnkle,
    umbralExtremo: 120,
    umbralReposo: 160,
  ),
  duracionMinimaRep: 0.6,
  reglasForma: [
    // 1) Profundidad: se decide AL TERMINAR la rep con el ángulo mínimo
    //    alcanzado (antes se evaluaba en cada frame y marcaba error incluso
    //    estando de pie).
    ReglaForma.alCompletar(
      id: 'profundidad_insuficiente',
      mensajeCorto: 'Baja más',
      mensajeLargo: 'Baja hasta que tus muslos queden casi paralelos al '
          'suelo, llevando la cadera hacia atrás como si fueras a sentarte.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
      ],
      medida: (ctx) => ctx.valorPrincipal,
      agregado: AgregadoRep.minimo,
      condicionRep: (r) => r.valor > 100,
    ),
    // 2) Torso demasiado inclinado hacia adelante (respecto a la vertical).
    //    Reemplaza a la antigua regla "espalda_curva", que medía el ángulo
    //    tronco-muslo y se cerraba de forma natural al bajar.
    ReglaForma.instantanea(
      id: 'torso_inclinado',
      mensajeCorto: 'Pecho arriba',
      mensajeLargo: 'Tu torso se va muy hacia adelante. Mantén el pecho '
          'alto y la mirada al frente mientras bajas.',
      severidad: Severidad.alta,
      articulaciones: const [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip,
      ],
      condicion: (ctx) {
        final inclinacion = ctx.inclinacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
        );
        return inclinacion != null && inclinacion > 55;
      },
    ),
  ],
);