import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'receta_ejercicio.dart';

/// Receta de las flexiones / lagartijas (vista LATERAL, teléfono en el suelo).
///
/// Conteo: ángulo del codo (hombro-codo-muñeca).
///   - Brazos estirados:   ~170°  (reposo si > 150°)
///   - Intento de bajada:  < 110° (extremo)
///   - Buena profundidad:  <= 95° (pecho cerca del suelo)
///
/// Igual que en la sentadilla, el extremo (110°) es más permisivo que la
/// profundidad buena (95°): una flexión corta SÍ cuenta, pero "a corregir".
///
/// Posición válida: cuerpo casi horizontal (línea hombro-tobillo a menos de
/// 35° del suelo). Así, de pie no cuenta nada.
final recetaFlexiones = RecetaEjercicio(
  id: 'pushup',
  nombre: 'Flexiones',
  tipo: TipoEjercicio.dinamico,
  vista: VistaCamara.lateral,
  orientacion: OrientacionSugerida.horizontal,
  ladoAutomatico: true,
  puntosRequeridos: const [
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightAnkle,
  ],
  posicionValida: (ctx) {
    final inclinacion = ctx.inclinacionHorizontal(
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightAnkle,
    );
    return inclinacion != null && inclinacion < 35;
  },
  mensajePosicion: 'Colócate en posición de flexión',
  deteccionRepeticion: DeteccionRepeticion.angulo(
    a: PoseLandmarkType.rightShoulder,
    b: PoseLandmarkType.rightElbow,
    c: PoseLandmarkType.rightWrist,
    umbralExtremo: 110,
    umbralReposo: 150,
  ),
  duracionMinimaRep: 0.5,
  reglasForma: [
    // 1) Cadera caída: lo más importante (carga la zona lumbar).
    ReglaForma.instantanea(
      id: 'cadera_caida',
      mensajeCorto: 'Sube la cadera',
      mensajeLargo: 'Tu cadera se está cayendo. Aprieta abdomen y glúteos '
          'para que el cuerpo baje y suba recto, como una tabla.',
      severidad: Severidad.alta,
      articulaciones: const [PoseLandmarkType.rightHip],
      condicion: (ctx) {
        final d = ctx.desviacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightAnkle,
          PoseLandmarkType.rightHip,
        );
        return d != null && d > 0.07;
      },
    ),
    // 2) Cadera demasiado alta ("en V"): le quita trabajo al pecho.
    ReglaForma.instantanea(
      id: 'cadera_elevada',
      mensajeCorto: 'Baja la cadera',
      mensajeLargo: 'Tu cadera está muy alta. Bájala hasta que hombros, '
          'cadera y tobillos queden en línea.',
      severidad: Severidad.media,
      articulaciones: const [PoseLandmarkType.rightHip],
      condicion: (ctx) {
        final d = ctx.desviacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightAnkle,
          PoseLandmarkType.rightHip,
        );
        return d != null && d < -0.09;
      },
    ),
    // 3) Profundidad: se decide al terminar con el ángulo mínimo del codo.
    ReglaForma.alCompletar(
      id: 'profundidad_flexion',
      mensajeCorto: 'Baja más el pecho',
      mensajeLargo: 'Baja hasta que el pecho quede cerca del suelo y los '
          'codos formen un ángulo recto.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
      ],
      medida: (ctx) => ctx.valorPrincipal,
      agregado: AgregadoRep.minimo,
      condicionRep: (r) => r.valor > 95,
    ),
    // 4) Ritmo: una flexión de menos de 0,8 s suele ser rebote sin control.
    ReglaForma.alCompletar(
      id: 'muy_rapido',
      mensajeCorto: 'Más despacio',
      mensajeLargo: 'Vas muy rápido. Baja en unos dos segundos, controlando '
          'el movimiento, y sube con fuerza.',
      severidad: Severidad.baja,
      condicionRep: (r) => r.duracionSegundos < 0.8,
    ),
  ],
);