import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/contexto_regla.dart';
import '../core/suavizador_pose.dart';

// Las recetas usan ParametrosSuavizado sin importar nada más.
export '../core/suavizador_pose.dart' show ParametrosSuavizado;

// ---------------------------------------------------------------------------
// CONTRATO DE LAS RECETAS
//
// Una receta describe un ejercicio como DATOS: qué medir, cuándo hay una
// repetición y qué errores corregir. El motor (motor_ejercicio.dart) es
// genérico y nunca se toca al agregar un ejercicio nuevo.
// ---------------------------------------------------------------------------

/// Severidad de un error. Decide qué mensaje se muestra primero:
/// los de seguridad (alta) van antes que los de rango o ritmo.
enum Severidad { alta, media, baja }

enum TipoEjercicio { dinamico, isometrico }

/// Desde dónde debe ver la cámara al usuario.
enum VistaCamara { lateral, frontal }

/// Orientación del teléfono que mejor funciona (se SUGIERE, no se fuerza).
enum OrientacionSugerida { vertical, horizontal }

/// Fases de una repetición dinámica (nombres genéricos):
///
///   reposo  -> posición inicial (de pie en sentadilla, brazo estirado en curl)
///   ida     -> yendo hacia la posición de esfuerzo
///   extremo -> en la posición de esfuerzo (abajo en sentadilla)
///   vuelta  -> regresando a la posición inicial
///
/// Una repetición se cuenta al pasar de vuelta -> reposo.
enum FaseMovimiento { reposo, ida, extremo, vuelta }

/// Cómo se resume una medida a lo largo de la repetición.
enum AgregadoRep { minimo, maximo }

/// Fases en las que, por defecto, se evalúan las reglas instantáneas:
/// durante el movimiento, no mientras descansas en la posición inicial.
const Set<FaseMovimiento> fasesDeMovimiento = {
  FaseMovimiento.ida,
  FaseMovimiento.extremo,
  FaseMovimiento.vuelta,
};

/// Define QUÉ se mide para detectar repeticiones y con qué umbrales.
///
/// Usa DOS umbrales distintos (histéresis): para entrar al extremo hay que
/// cruzar [umbralExtremo] y para volver al reposo hay que cruzar
/// [umbralReposo]. La zona entre ambos es "neutra", así el ruido alrededor
/// de un solo valor no genera reps fantasma.
class DeteccionRepeticion {
  /// Valor que se sigue en cada frame (normalmente un ángulo).
  final double? Function(ContextoRegla ctx) metrica;

  final double umbralExtremo;
  final double umbralReposo;

  /// true  -> el valor BAJA al hacer el esfuerzo (ángulo de rodilla en sentadilla)
  /// false -> el valor SUBE al hacer el esfuerzo (apertura en jumping jacks)
  final bool extremoEsMenor;

  /// Articulaciones que intervienen (para documentación / resaltado).
  final List<PoseLandmarkType> articulaciones;

  const DeteccionRepeticion({
    required this.metrica,
    required this.umbralExtremo,
    required this.umbralReposo,
    this.extremoEsMenor = true,
    this.articulaciones = const [],
  });

  /// Atajo para el caso más común: repetición basada en el ángulo A-B-C,
  /// donde el ángulo se cierra al hacer el esfuerzo.
  factory DeteccionRepeticion.angulo({
    required PoseLandmarkType a,
    required PoseLandmarkType b, // vértice
    required PoseLandmarkType c,
    required double umbralExtremo,
    required double umbralReposo,
  }) {
    return DeteccionRepeticion(
      metrica: (ctx) => ctx.angulo(a, b, c),
      umbralExtremo: umbralExtremo,
      umbralReposo: umbralReposo,
      extremoEsMenor: true,
      articulaciones: [a, b, c],
    );
  }

  bool estaEnExtremo(double v) =>
      extremoEsMenor ? v < umbralExtremo : v > umbralExtremo;

  bool estaEnReposo(double v) =>
      extremoEsMenor ? v > umbralReposo : v < umbralReposo;
}

/// Una regla de forma: si se cumple, hay un error de técnica.
///
/// Hay dos tipos:
///
/// 1. INSTANTÁNEA: se revisa en cada frame (ej. "pecho arriba").
///    Para evitar falsos avisos por ruido, el error solo se activa si se
///    cumple durante [msMinimos] milisegundos seguidos (Fase I.5).
///
/// 2. AL COMPLETAR: mide algo durante toda la repetición (ej. el ángulo
///    mínimo alcanzado) y decide al final si fue suficiente
///    (ej. "baja más"). Así no se marca error mientras vas bajando.
class ReglaForma {
  final String id; // se guarda en Supabase (eventos_repeticion.errores)
  final String mensajeCorto; // 2-4 palabras: se dice en vivo
  final String mensajeLargo; // explicación si el error se repite
  final Severidad severidad;

  /// Articulaciones implicadas (lado derecho): se resaltan en el esqueleto.
  final List<PoseLandmarkType> articulaciones;

  // --- Instantánea ---
  final Set<FaseMovimiento> fases;

  /// Frames "de referencia" (a 20 FPS) que debe cumplirse la condición.
  /// Se conserva para no reescribir las recetas: el motor usa [msMinimos].
  final int framesMinimos;

  /// Fase I.5: tiempo mínimo (ms) que debe cumplirse la condición para
  /// activar el error, igual en cualquier teléfono. Si no se indica, se
  /// deriva de [framesMinimos] a 20 FPS: 3 frames → 100 ms, 2 → 50 ms.
  final int msMinimos;

  /// Intervalo entre frames a 20 FPS (la referencia de los umbrales).
  static const int msPorFrameReferencia = 50;
  final bool Function(ContextoRegla ctx)? condicion;

  // --- Al completar ---
  final double? Function(ContextoRegla ctx)? medida;
  final AgregadoRep agregado;
  final bool Function(ResumenRep r)? condicionRep;

  const ReglaForma.instantanea({
    required this.id,
    required this.mensajeCorto,
    required this.mensajeLargo,
    required this.severidad,
    required bool Function(ContextoRegla ctx) this.condicion,
    this.articulaciones = const [],
    this.fases = fasesDeMovimiento,
    this.framesMinimos = 3,
    int? msMinimos,
  })  : msMinimos =
            msMinimos ?? (framesMinimos - 1) * msPorFrameReferencia,
        medida = null,
        agregado = AgregadoRep.minimo,
        condicionRep = null;

  const ReglaForma.alCompletar({
    required this.id,
    required this.mensajeCorto,
    required this.mensajeLargo,
    required this.severidad,
    required bool Function(ResumenRep r) this.condicionRep,
    this.medida,
    this.agregado = AgregadoRep.minimo,
    this.articulaciones = const [],
  })  : condicion = null,
        fases = const {},
        framesMinimos = 1,
        msMinimos = 0;

  bool get esAlCompletar => condicionRep != null;

  /// Compatibilidad con el código anterior (pantalla_camara usa .mensaje).
  String get mensaje => mensajeCorto;
}

/// La "receta" de un ejercicio: configuración que el motor interpreta.
/// Agregar un ejercicio nuevo = crear otra receta, sin tocar el motor.
class RecetaEjercicio {
  final String id;
  final String nombre;
  final TipoEjercicio tipo;

  // --- Encuadre ---
  final VistaCamara vista;
  final OrientacionSugerida orientacion;

  /// Articulaciones que deben verse para empezar. En vista lateral se
  /// escriben las del lado DERECHO; si [ladoAutomatico] es true, el motor
  /// usará el lado que mejor se vea.
  final List<PoseLandmarkType> puntosRequeridos;
  final bool ladoAutomatico;

  // --- Posición válida ---
  /// Condición para considerar que el usuario está "en posición"
  /// (ej. en plancha: cuerpo casi horizontal). Si no se cumple, no se
  /// cuenta ni se evalúa la forma. null = siempre válida.
  final bool Function(ContextoRegla ctx)? posicionValida;
  final String mensajePosicion;

  // --- Conteo y forma ---
  final DeteccionRepeticion? deteccionRepeticion;

  /// Reps más rápidas que esto se ignoran (suelen ser ruido).
  final double duracionMinimaRep;

  /// Cuánto se suaviza la pose (filtro One Euro, ver SuavizadorPose).
  /// El valor por defecto sirve para movimientos normales; los ejercicios
  /// explosivos (jumping jacks) usan ParametrosSuavizado.rapido.
  final ParametrosSuavizado suavizado;
  final List<ReglaForma> reglasForma;

  const RecetaEjercicio({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.puntosRequeridos,
    this.vista = VistaCamara.lateral,
    this.orientacion = OrientacionSugerida.vertical,
    this.ladoAutomatico = true,
    this.posicionValida,
    this.mensajePosicion = 'Colócate en posición',
    this.deteccionRepeticion,
    this.duracionMinimaRep = 0.5,
    this.suavizado = ParametrosSuavizado.porDefecto,
    this.reglasForma = const [],
  });
}