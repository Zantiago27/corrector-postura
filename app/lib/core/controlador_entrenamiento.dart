import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../ejercicios/receta_ejercicio.dart';
import 'coach_entrenamiento.dart';
import 'motor_ejercicio.dart';

/// Estado de la sesión (Fase D: flujo manos libres).
///
///   preparando --(encuadrado y quieto 2 s)--> cuentaRegresiva
///   cuentaRegresiva --(3, 2, 1)--> entrenando
///   cuentaRegresiva --(sales de cuadro)--> preparando
///   entrenando --(fuera de cuadro > 3 s)--> pausado
///   pausado --(vuelves al cuadro)--> entrenando
///
/// El botón "Empezar" y el comando de voz saltan directo a entrenando.
enum EstadoSesion { preparando, cuentaRegresiva, entrenando, pausado }

/// Lógica de una sesión de entrenamiento, separada de la pantalla.
///
/// Reparto de responsabilidades:
///   - PantallaCamara: cámara, permisos, voz (TTS/STT) y dibujo.
///   - ControladorEntrenamiento (este archivo): estados de la sesión,
///     motor + coach, y los datos de la serie que luego se guardan.
///
/// Es Dart puro (sin Flutter): la pantalla le pasa cada pose y él devuelve
/// qué decir. Así la lógica se puede probar sin cámara.
class ControladorEntrenamiento {
  final RecetaEjercicio receta;
  final MotorEjercicio motor;
  late final CoachEntrenamiento coach;

  // --- Ajustes del flujo manos libres ---
  static const esperaAutoInicio = Duration(seconds: 2);
  static const segundosCuenta = 3;
  static const toleranciaCuenta = Duration(milliseconds: 700);
  static const esperaPausa = Duration(seconds: 3);

  ControladorEntrenamiento(this.receta, {DateTime? ahora})
      : motor = MotorEjercicio(receta),
        _inicio = ahora ?? DateTime.now() {
    coach = CoachEntrenamiento(
      esIsometrico: esIsometrico,
      mensajePosicion: receta.mensajePosicion,
      articulacionesDe: motor.articulacionesDe,
    );
  }

  EstadoSesion _estado = EstadoSesion.preparando;
  bool _encuadreOk = false;
  EvaluacionFrame? _ultima;
  final List<RepeticionCompletada> _reps = [];
  DateTime _inicio;

  // Preparación y cuenta regresiva
  DateTime? _encuadradoDesde;
  DateTime? _cuentaDesde;
  DateTime? _perdidoEnCuentaDesde;
  int _ultimoNumeroDicho = 0;

  // Pausa automática
  DateTime? _sinCuerpoDesde;
  DateTime? _pausaDesde;
  Duration _tiempoPausado = Duration.zero;

  // =========================================================================
  // LECTURA (para la UI y el guardado)
  // =========================================================================

  EstadoSesion get estado => _estado;
  bool get esIsometrico => receta.tipo == TipoEjercicio.isometrico;

  /// true desde que empieza la serie (incluye la pausa automática).
  bool get entrenando =>
      _estado == EstadoSesion.entrenando || _estado == EstadoSesion.pausado;
  bool get pausado => _estado == EstadoSesion.pausado;
  bool get enCuentaRegresiva => _estado == EstadoSesion.cuentaRegresiva;
  bool get encuadreOk => _encuadreOk;
  DateTime get inicio => _inicio;

  int get repsTotales => motor.repeticiones;
  int get repsCorrectas => motor.repsCorrectas;
  int get repsIncorrectas => motor.repsIncorrectas;
  double get segundos => motor.segundosMantenidos;
  List<RepeticionCompletada> get reps => List.unmodifiable(_reps);

  /// Progreso (0..1) de los 2 s de espera antes de la cuenta regresiva.
  double progresoAutoInicio(DateTime ahora) {
    final desde = _encuadradoDesde;
    if (_estado != EstadoSesion.preparando || desde == null) return 0;
    final p = ahora.difference(desde).inMilliseconds /
        esperaAutoInicio.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }

  /// Número que se muestra en la cuenta regresiva (3, 2, 1) o null.
  int? numeroCuenta(DateTime ahora) {
    final desde = _cuentaDesde;
    if (!enCuentaRegresiva || desde == null) return null;
    final restante = segundosCuenta - ahora.difference(desde).inSeconds;
    return restante.clamp(1, segundosCuenta);
  }

  /// Mensaje del banner de feedback.
  MensajeCoach mensaje(DateTime ahora) => coach.mensaje(ahora);

  /// Articulaciones a resaltar en el esqueleto.
  Set<PoseLandmarkType> resaltadas(DateTime ahora) =>
      _estado == EstadoSesion.entrenando
          ? coach.articulacionesResaltadas(ahora)
          : const {};

  /// Color del esqueleto: verde si todo va bien, naranja si hay que corregir.
  bool formaCorrecta(DateTime ahora) {
    final e = _ultima;
    if (_estado != EstadoSesion.entrenando || e == null) return true;
    return e.enPosicion && e.formaCorrecta && resaltadas(ahora).isEmpty;
  }

  /// Duración que se guarda: tiempo en posición (isométricos) o tiempo
  /// real de entrenamiento SIN contar las pausas.
  int duracionSegundos(DateTime ahora) {
    if (esIsometrico) return segundos.round();
    final pausaEnCurso =
        _pausaDesde == null ? Duration.zero : ahora.difference(_pausaDesde!);
    final activo = ahora.difference(_inicio) - _tiempoPausado - pausaEnCurso;
    return activo.isNegative ? 0 : activo.inSeconds;
  }

  // =========================================================================
  // ENTRADA
  // =========================================================================

  /// Procesa la pose de un frame ([pose] = null si ML Kit no vio a nadie).
  /// Devuelve lo que habría que decir en voz alta (o null).
  Anuncio? procesar(Pose? pose, DateTime ahora) {
    return switch (_estado) {
      EstadoSesion.preparando => _procesarPreparacion(pose, ahora),
      EstadoSesion.cuentaRegresiva => _procesarCuenta(pose, ahora),
      EstadoSesion.entrenando ||
      EstadoSesion.pausado =>
        _procesarEntrenamiento(pose, ahora),
    };
  }

  /// Botón "Empezar" o comando de voz: empieza YA (sin cuenta regresiva).
  /// Devuelve false si el cuerpo aún no está encuadrado.
  bool empezar(DateTime ahora) {
    if (!_encuadreOk || entrenando) return false;
    _iniciarEntrenamiento(ahora);
    return true;
  }

  /// Empieza la serie de cero (botón reiniciar).
  void reiniciarSerie(DateTime ahora) {
    motor.reiniciar();
    coach.reiniciar();
    _reps.clear();
    _ultima = null;
    _inicio = ahora;
    _tiempoPausado = Duration.zero;
    _pausaDesde = null;
    _sinCuerpoDesde = null;
    if (_estado == EstadoSesion.pausado) _estado = EstadoSesion.entrenando;
  }

  /// Pausa técnica (cambio de cámara, app en segundo plano).
  void pausar() => motor.pausar();

  // =========================================================================
  // ESTADOS
  // =========================================================================

  /// "Prepárate": espera a que el cuerpo esté encuadrado y quieto 2 s.
  Anuncio? _procesarPreparacion(Pose? pose, DateTime ahora) {
    _encuadreOk = pose != null && motor.cuerpoEncuadrado(pose);
    if (!_encuadreOk) {
      _encuadradoDesde = null;
      return null;
    }
    final desde = _encuadradoDesde ??= ahora;
    if (ahora.difference(desde) < esperaAutoInicio) return null;

    // Arranca la cuenta regresiva.
    _estado = EstadoSesion.cuentaRegresiva;
    _cuentaDesde = ahora;
    _perdidoEnCuentaDesde = null;
    _ultimoNumeroDicho = segundosCuenta;
    return const Anuncio('$segundosCuenta', prioritario: true);
  }

  /// Cuenta regresiva 3-2-1. Se cancela si sales de cuadro.
  Anuncio? _procesarCuenta(Pose? pose, DateTime ahora) {
    _encuadreOk = pose != null && motor.cuerpoEncuadrado(pose);
    if (!_encuadreOk) {
      final perdido = _perdidoEnCuentaDesde ??= ahora;
      if (ahora.difference(perdido) > toleranciaCuenta) {
        _estado = EstadoSesion.preparando;
        _encuadradoDesde = null;
        _cuentaDesde = null;
        return const Anuncio('Vuelve a colocarte', prioritario: true);
      }
    } else {
      _perdidoEnCuentaDesde = null;
    }

    final transcurrido = ahora.difference(_cuentaDesde!);
    if (transcurrido >= const Duration(seconds: segundosCuenta)) {
      _iniciarEntrenamiento(ahora);
      return const Anuncio('¡Vamos!', prioritario: true);
    }
    final numero = segundosCuenta - transcurrido.inSeconds;
    if (numero < _ultimoNumeroDicho) {
      _ultimoNumeroDicho = numero;
      return Anuncio('$numero', prioritario: true);
    }
    return null;
  }

  void _iniciarEntrenamiento(DateTime ahora) {
    reiniciarSerie(ahora);
    _estado = EstadoSesion.entrenando;
    _cuentaDesde = null;
  }

  /// Entrenando (y pausa automática si sales de cuadro más de 3 s).
  Anuncio? _procesarEntrenamiento(Pose? pose, DateTime ahora) {
    final e = pose == null ? null : motor.evaluar(pose, instante: ahora);

    if (e == null) {
      // No se ven los puntos necesarios: no se cuenta ni se corrige.
      motor.pausar();
      _ultima = null;
      coach.sinCuerpo(ahora); // solo para el banner; la voz la manejamos aquí
      if (_estado == EstadoSesion.entrenando) {
        final desde = _sinCuerpoDesde ??= ahora;
        if (ahora.difference(desde) >= esperaPausa) {
          _estado = EstadoSesion.pausado;
          _pausaDesde = desde; // la pausa cuenta desde que saliste
          return const Anuncio('Pausa. Vuelve al cuadro para seguir');
        }
      }
      return null;
    }

    // Se te ve otra vez.
    _sinCuerpoDesde = null;
    Anuncio? reanudacion;
    if (_estado == EstadoSesion.pausado) {
      _tiempoPausado += ahora.difference(_pausaDesde!);
      _pausaDesde = null;
      _estado = EstadoSesion.entrenando;
      reanudacion = const Anuncio('¡Seguimos!', prioritario: true);
    }

    _ultima = e;
    final rep = e.repCompletada;
    if (rep != null) _reps.add(rep);
    final anuncio = coach.procesar(e, ahora);
    return reanudacion ?? anuncio;
  }
}