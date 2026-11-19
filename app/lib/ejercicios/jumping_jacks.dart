import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/contexto_regla.dart';
import 'receta_ejercicio.dart';

// ---------------------------------------------------------------------------
// Medidas propias del jumping jack (vista FRONTAL).
// ---------------------------------------------------------------------------

/// Ángulo de un brazo respecto al tronco (cadera-hombro-muñeca):
///   ~15° brazo pegado al cuerpo · ~90° en cruz · ~170° sobre la cabeza.
double? _anguloBrazo(ContextoRegla ctx, {required bool izquierdo}) {
  return izquierdo
      ? ctx.angulo(PoseLandmarkType.leftHip, PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftWrist)
      : ctx.angulo(PoseLandmarkType.rightHip, PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightWrist);
}

/// Apertura de brazos: promedio de los dos lados. Es la métrica del conteo.
double? _aperturaBrazos(ContextoRegla ctx) {
  final i = _anguloBrazo(ctx, izquierdo: true);
  final d = _anguloBrazo(ctx, izquierdo: false);
  if (i == null || d == null) return null;
  return (i + d) / 2;
}

/// Separación de tobillos dividida por el ancho de hombros. Así no depende
/// de lo lejos que estés de la cámara. ~0.6 juntas · ~1.8 bien abiertas.
double? _aperturaPiernas(ContextoRegla ctx) {
  final tobillos =
      ctx.dist(PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle);
  final hombros =
      ctx.dist(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
  if (tobillos == null || hombros == null || hombros < 1) return null;
  return tobillos / hombros;
}

/// Receta de los jumping jacks / polichinelas (vista FRONTAL).
///
/// Conteo: apertura media de los brazos (sube al abrir, por eso
/// extremoEsMenor = false).
///   - Cerrado (reposo):   < 50°
///   - Abierto (extremo):  > 120°
///   - Brazos completos:   >= 150° (manos sobre la cabeza)
///
/// Es un movimiento rápido: usa el suavizado "rápido" (One Euro con más
/// beta) para no ir con retraso, y se aceptan reps cortas (0.3 s).
final recetaJumpingJacks = RecetaEjercicio(
  id: 'jumping_jack',
  nombre: 'Jumping jacks',
  tipo: TipoEjercicio.dinamico,
  vista: VistaCamara.frontal,
  orientacion: OrientacionSugerida.vertical,
  ladoAutomatico: false, // de frente se usan los dos lados
  puntosRequeridos: const [
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ],
  suavizado: ParametrosSuavizado.rapido,
  deteccionRepeticion: const DeteccionRepeticion(
    metrica: _aperturaBrazos,
    umbralExtremo: 120,
    umbralReposo: 50,
    extremoEsMenor: false,
    articulaciones: [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
    ],
  ),
  duracionMinimaRep: 0.3,
  reglasForma: [
    // 1) Brazos sin subir del todo (máxima apertura de la rep).
    ReglaForma.alCompletar(
      id: 'brazos_incompletos',
      mensajeCorto: 'Brazos arriba',
      mensajeLargo: 'Sube los brazos por completo, hasta que las manos se '
          'junten sobre la cabeza.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
      ],
      medida: (ctx) => ctx.valorPrincipal,
      agregado: AgregadoRep.maximo,
      condicionRep: (r) => r.valor < 150,
    ),
    // 2) Piernas poco abiertas (máxima apertura de la rep).
    ReglaForma.alCompletar(
      id: 'piernas_cerradas',
      mensajeCorto: 'Abre más las piernas',
      mensajeLargo: 'Al saltar, separa los pies más que el ancho de tus '
          'hombros y vuelve a juntarlos.',
      severidad: Severidad.media,
      articulaciones: const [
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ],
      medida: _aperturaPiernas,
      agregado: AgregadoRep.maximo,
      condicionRep: (r) => r.valor < 1.3,
    ),
    // 3) Un brazo sube bastante menos que el otro (en el punto más abierto).
    ReglaForma.instantanea(
      id: 'asimetria_brazos',
      mensajeCorto: 'Brazos parejos',
      mensajeLargo: 'Un brazo sube menos que el otro. Intenta que los dos '
          'lleguen a la misma altura.',
      severidad: Severidad.baja,
      fases: const {FaseMovimiento.extremo},
      framesMinimos: 2,
      articulaciones: const [
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
      ],
      condicion: (ctx) {
        final i = _anguloBrazo(ctx, izquierdo: true);
        final d = _anguloBrazo(ctx, izquierdo: false);
        return i != null && d != null && (i - d).abs() > 30;
      },
    ),
  ],
);