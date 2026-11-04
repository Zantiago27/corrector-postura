import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'receta_ejercicio.dart';

/// Receta del curl de bíceps (vista LATERAL, brazo más visible).
///
/// Conteo: ángulo del codo (hombro-codo-muñeca).
///   - Brazo estirado:   ~170°  (reposo si > 140°)
///   - Intento de curl:  < 75°  (extremo)
///   - Curl completo:    <= 55°
///
/// Igual que en la sentadilla, el extremo (75°) es más permisivo que el
/// curl completo (55°): un curl corto cuenta, pero como "a corregir".
final recetaCurl = RecetaEjercicio(
  id: 'curl',
  nombre: 'Curl de bíceps',
  tipo: TipoEjercicio.dinamico,
  vista: VistaCamara.lateral,
  orientacion: OrientacionSugerida.vertical,
  ladoAutomatico: true,
  puntosRequeridos: const [
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.rightHip,
  ],
  deteccionRepeticion: DeteccionRepeticion.angulo(
    a: PoseLandmarkType.rightShoulder,
    b: PoseLandmarkType.rightElbow,
    c: PoseLandmarkType.rightWrist,
    umbralExtremo: 75,
    umbralReposo: 140,
  ),
  duracionMinimaRep: 0.6,
  reglasForma: [
    // 1) El codo debe quedarse pegado al costado. Si el brazo se va hacia
    //    adelante (usar impulso), crece el ángulo codo-hombro-cadera.
    ReglaForma.instantanea(
      id: 'codo_separado',
      mensajeCorto: 'Codo pegado',
      mensajeLargo: 'Tu codo se adelanta. Pégalo al costado y mueve solo el '
          'antebrazo; si no puedes, usa menos peso.',
      severidad: Severidad.alta,
      articulaciones: const [
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightShoulder,
      ],
      condicion: (ctx) {
        final a = ctx.angulo(
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
        );
        return a != null && a > 40;
      },
    ),
    // 2) Balanceo del tronco para "ayudarse" a subir el peso.
    ReglaForma.instantanea(
      id: 'tronco_balanceo',
      mensajeCorto: 'No balancees',
      mensajeLargo: 'Estás moviendo el tronco para subir el peso. Mantén la '
          'espalda quieta y recta durante todo el movimiento.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip,
      ],
      condicion: (ctx) {
        final inclinacion = ctx.inclinacion(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
        );
        return inclinacion != null && inclinacion > 15;
      },
    ),
    // 3) Rango incompleto: se decide al terminar con el ángulo mínimo.
    ReglaForma.alCompletar(
      id: 'curl_incompleto',
      mensajeCorto: 'Sube más',
      mensajeLargo: 'Completa el movimiento: sube la mano hasta casi tocar '
          'el hombro antes de bajar.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist,
      ],
      medida: (ctx) => ctx.valorPrincipal,
      agregado: AgregadoRep.minimo,
      condicionRep: (r) => r.valor > 55,
    ),
  ],
);