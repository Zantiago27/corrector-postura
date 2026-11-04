import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'motor_ejercicio.dart';

// ---------------------------------------------------------------------------
// COACH DE ENTRENAMIENTO
//
// El motor (motor_ejercicio.dart) dice QUÉ pasa: reps, errores, fases.
// El coach decide CÓMO comunicarlo para que el usuario aprenda sin
// saturarse:
//
//   1. Un solo mensaje visible a la vez (el más grave).
//   2. En vivo, mensajes cortos (2-4 palabras) y como máximo una vez por rep.
//   3. Explicación larga solo si el mismo error se repite 3 reps seguidas,
//      y una sola vez por error en cada serie.
//   4. Pausa mínima entre avisos de voz; el veredicto de la rep tiene prioridad.
//   5. Rep correcta: la voz dice solo el número de reps correctas.
//   6. Refuerzo positivo solo al corregir un error o al encadenar buenas reps.
//
// Es Dart puro (sin Flutter): se prueba con tests y no sabe nada de la
// cámara, de la voz ni de la pantalla. Recibe evaluaciones y devuelve
// "anuncios" (qué decir) y un "mensaje" (qué mostrar).
// ---------------------------------------------------------------------------

/// Tono visual del mensaje en pantalla.
enum TonoMensaje { ok, corrige, info }

/// Lo que se muestra en el banner de feedback.
class MensajeCoach {
  final TonoMensaje tono;
  final String titulo; // corto y grande ("Baja más")
  final String? detalle; // opcional, más pequeño (la explicación larga)
  final bool esExplicacion;

  const MensajeCoach(
    this.tono,
    this.titulo, {
    this.detalle,
    this.esExplicacion = false,
  });

  /// Clave estable: si no cambia, la UI no anima (evita parpadeos).
  String get clave => '${tono.name}|$titulo|${detalle ?? ''}';
}

/// Algo que el coach quiere decir en voz alta.
class Anuncio {
  final String texto;

  /// true = es el veredicto de una rep: debe sonar YA, cortando un aviso
  /// corto si lo hubiera (nunca corta una explicación larga).
  final bool prioritario;

  const Anuncio(this.texto, {this.prioritario = false});

  @override
  String toString() => 'Anuncio("$texto", prioritario: $prioritario)';
}

class CoachEntrenamiento {
  final bool esIsometrico;
  final String mensajePosicion;

  /// Traduce una regla a las articulaciones REALES a resaltar
  /// (normalmente MotorEjercicio.articulacionesDe).
  final Set<PoseLandmarkType> Function(ReglaForma regla) articulacionesDe;

  /// Silencio mínimo después de un aviso de corrección.
  final Duration pausaVoz;

  /// Silencio mínimo después de un veredicto (un número es muy corto).
  final Duration pausaVeredicto;

  // --- Ajustes de comportamiento (en un solo lugar para calibrarlos) ---
  static const int repsParaExplicar = 3;
  static const double hitoSegundos = 15; // isométricos: "15 segundos"
  static const _retencionVivo = Duration(milliseconds: 1200);
  static const _retencionVeredicto = Duration(milliseconds: 1800);
  static const _retencionExplicacion = Duration(seconds: 6);
  static const _retencionResaltado = Duration(milliseconds: 1500);
  static const _repetirAvisoIsometrico = Duration(seconds: 6);
  static const _esperaAvisoPosicion = Duration(seconds: 2);
  static const _repetirAvisoPosicion = Duration(seconds: 8);
  static const _pausaRefuerzo = Duration(seconds: 10);

  CoachEntrenamiento({
    required this.esIsometrico,
    this.mensajePosicion = 'Colócate en posición',
    Set<PoseLandmarkType> Function(ReglaForma regla)? articulacionesDe,
    this.pausaVoz = const Duration(seconds: 3),
    this.pausaVeredicto = const Duration(milliseconds: 800),
  }) : articulacionesDe = articulacionesDe ?? _sinArticulaciones;

  static Set<PoseLandmarkType> _sinArticulaciones(ReglaForma _) => const {};

  // --- Serie ---
  final List<bool> _veredictos = [];
  int _idVeredicto = 0;
  int _racha = 0; // correctas seguidas
  final Map<String, int> _consecutivos = {}; // reps seguidas con cada error
  final Set<String> _explicados = {}; // errores ya explicados en la serie
  final Set<String> _dichosEnRep = {}; // avisos ya dichos en la rep en curso

  // --- Voz ---
  DateTime? _vozLibreDesde;
  DateTime? _explicandoHasta;

  // --- Pantalla ---
  MensajeCoach? _fijado;
  int _prioridadFijado = 0;
  DateTime? _fijadoHasta;
  Set<PoseLandmarkType> _resaltadoRep = const {};
  DateTime? _resaltadoHasta;
  EvaluacionFrame? _ultimaEval;
  bool _sinCuerpo = false;

  // --- Isométricos ---
  final Map<String, DateTime> _ultimoAvisoPorError = {};
  final Map<String, int> _activaciones = {};
  Set<String> _activosPrevios = {};
  double _proximoHito = hitoSegundos;
  DateTime? _ultimoRefuerzo;

  // --- Posición ---
  DateTime? _fueraDesde;
  DateTime? _ultimoAvisoPosicion;

  // =========================================================================
  // LECTURA (para la UI)
  // =========================================================================

  /// Historial de la serie: true = correcta, false = a corregir.
  List<bool> get veredictos => List.unmodifiable(_veredictos);

  /// Cambia cada vez que termina una rep (dispara el destello).
  int get idVeredicto => _idVeredicto;
  bool? get ultimoVeredictoCorrecto =>
      _veredictos.isEmpty ? null : _veredictos.last;
  int get repsCorrectas => _veredictos.where((v) => v).length;

  /// Mensaje a mostrar ahora mismo en el banner.
  MensajeCoach mensaje(DateTime ahora) {
    final hasta = _fijadoHasta;
    if (_fijado != null && hasta != null && ahora.isBefore(hasta)) {
      return _fijado!;
    }
    // Fuera de cuadro: solo se avisa si dura más de 2 s, para que un frame
    // perdido no haga parpadear el banner.
    final fueraDesde = _fueraDesde;
    if (_sinCuerpo &&
        fueraDesde != null &&
        ahora.difference(fueraDesde) >= _esperaAvisoPosicion) {
      return const MensajeCoach(TonoMensaje.info, 'Vuelve al cuadro',
          detalle: 'No te veo completo');
    }
    final e = _ultimaEval;
    if (e != null && !e.enPosicion) {
      return MensajeCoach(TonoMensaje.info, mensajePosicion);
    }
    if (esIsometrico) {
      return const MensajeCoach(TonoMensaje.ok, 'Mantén la posición');
    }
    if (_veredictos.isEmpty &&
        (e == null || e.fase == FaseMovimiento.reposo)) {
      return const MensajeCoach(TonoMensaje.info, 'Empieza cuando quieras');
    }
    return const MensajeCoach(TonoMensaje.ok, 'Sigue así');
  }

  /// Articulaciones a resaltar en el esqueleto ahora mismo.
  Set<PoseLandmarkType> articulacionesResaltadas(DateTime ahora) {
    if (_sinCuerpo) return const {};
    final enVivo = _ultimaEval?.articulacionesConError ?? const {};
    final hasta = _resaltadoHasta;
    if (hasta != null && ahora.isBefore(hasta)) {
      return {..._resaltadoRep, ...enVivo};
    }
    return enVivo;
  }

  // =========================================================================
  // ENTRADA (desde el controlador, en cada frame)
  // =========================================================================

  /// Empieza una serie nueva.
  void reiniciar() {
    _veredictos.clear();
    _idVeredicto = 0;
    _racha = 0;
    _consecutivos.clear();
    _explicados.clear();
    _dichosEnRep.clear();
    _vozLibreDesde = null;
    _explicandoHasta = null;
    _fijado = null;
    _prioridadFijado = 0;
    _fijadoHasta = null;
    _resaltadoRep = const {};
    _resaltadoHasta = null;
    _ultimaEval = null;
    _sinCuerpo = false;
    _ultimoAvisoPorError.clear();
    _activaciones.clear();
    _activosPrevios = {};
    _proximoHito = hitoSegundos;
    _ultimoRefuerzo = null;
    _fueraDesde = null;
    _ultimoAvisoPosicion = null;
  }

  /// Procesa la evaluación de un frame. Devuelve qué decir (o null).
  Anuncio? procesar(EvaluacionFrame e, DateTime ahora) {
    _ultimaEval = e;
    _sinCuerpo = false;
    if (!e.enPosicion) return _avisoPosicion(ahora, mensajePosicion);
    _fueraDesde = null;
    return esIsometrico
        ? _procesarIsometrico(e, ahora)
        : _procesarDinamico(e, ahora);
  }

  /// El motor no ve el cuerpo (devolvió null).
  Anuncio? sinCuerpo(DateTime ahora) {
    _sinCuerpo = true;
    _activosPrevios = {};
    return _avisoPosicion(ahora, 'Vuelve al cuadro');
  }

  // =========================================================================
  // DINÁMICOS
  // =========================================================================

  Anuncio? _procesarDinamico(EvaluacionFrame e, DateTime ahora) {
    Anuncio? anuncio;

    // 1) ¿Terminó una rep? (antes de limpiar lo dicho en la rep)
    final rep = e.repCompletada;
    if (rep != null) anuncio = _alCompletarRep(rep, ahora);
    if (e.fase == FaseMovimiento.reposo) _dichosEnRep.clear();

    // 2) Error en vivo: se MUESTRA siempre; se DICE una vez por rep.
    final error = e.errorPrincipal;
    if (error != null) {
      _fijar(MensajeCoach(TonoMensaje.corrige, error.mensajeCorto), 1, ahora,
          _retencionVivo);
      if (anuncio == null &&
          !_dichosEnRep.contains(error.id) &&
          _puedeHablar(ahora)) {
        _dichosEnRep.add(error.id);
        anuncio = _hablar(error.mensajeCorto, ahora);
      }
    }
    return anuncio;
  }

  Anuncio? _alCompletarRep(RepeticionCompletada rep, DateTime ahora) {
    final previaIncorrecta = _veredictos.isNotEmpty && !_veredictos.last;
    _veredictos.add(rep.esCorrecta);
    _idVeredicto++;
    final explicando = _estaExplicando(ahora);

    // --- Rep correcta ---
    if (rep.esCorrecta) {
      _racha++;
      _consecutivos.clear();
      final n = repsCorrectas;
      final String texto;
      final MensajeCoach m;
      if (previaIncorrecta) {
        texto = '¡Eso es! $n';
        m = const MensajeCoach(TonoMensaje.ok, '¡Corregido!',
            detalle: 'Así se hace');
      } else if (_racha == 3 || (_racha > 3 && _racha % 5 == 0)) {
        texto = '$n, ¡muy bien!';
        m = MensajeCoach(TonoMensaje.ok, '¡$_racha seguidas!');
      } else {
        texto = '$n';
        m = const MensajeCoach(TonoMensaje.ok, '¡Bien hecha!');
      }
      _fijar(m, 2, ahora, _retencionVeredicto);
      return explicando ? null : _hablar(texto, ahora, prioritario: true);
    }

    // --- Rep a corregir ---
    _racha = 0;
    _consecutivos.removeWhere((id, _) => !rep.errores.contains(id));
    for (final id in rep.errores) {
      _consecutivos[id] = (_consecutivos[id] ?? 0) + 1;
    }
    final principal = rep.errorPrincipal;
    if (principal == null) return null;

    // ¿Algún error se repite lo bastante como para explicarlo?
    // (se recorren por prioridad: el más grave primero)
    final aExplicar = rep.reglasRotas.where((r) =>
        (_consecutivos[r.id] ?? 0) >= repsParaExplicar &&
        !_explicados.contains(r.id));
    if (aExplicar.isNotEmpty && !explicando) {
      final regla = aExplicar.first;
      _explicados.add(regla.id);
      _consecutivos[regla.id] = 0;
      _resaltar(regla, ahora);
      _fijar(
        MensajeCoach(TonoMensaje.corrige, regla.mensajeCorto,
            detalle: regla.mensajeLargo, esExplicacion: true),
        3,
        ahora,
        _retencionExplicacion,
      );
      return _hablar(regla.mensajeLargo, ahora,
          prioritario: true, esExplicacion: true);
    }

    _resaltar(principal, ahora);
    _fijar(MensajeCoach(TonoMensaje.corrige, principal.mensajeCorto), 2, ahora,
        _retencionVeredicto);
    // Si ya se lo dijimos durante la rep, no lo repetimos: basta el destello.
    if (explicando || _dichosEnRep.contains(principal.id)) return null;
    return _hablar(principal.mensajeCorto, ahora, prioritario: true);
  }

  // =========================================================================
  // ISOMÉTRICOS
  // =========================================================================

  Anuncio? _procesarIsometrico(EvaluacionFrame e, DateTime ahora) {
    final activos = e.erroresActivos.map((r) => r.id).toSet();
    for (final id in activos.difference(_activosPrevios)) {
      _activaciones[id] = (_activaciones[id] ?? 0) + 1;
    }
    final veniaConErrores = _activosPrevios.isNotEmpty;
    _activosPrevios = activos;

    final error = e.errorPrincipal;
    if (error != null) {
      // El mismo error apareció 3 veces: toca explicarlo (una sola vez).
      final explicar = (_activaciones[error.id] ?? 0) >= repsParaExplicar &&
          !_explicados.contains(error.id);
      if (explicar && _puedeHablar(ahora)) {
        _explicados.add(error.id);
        _ultimoAvisoPorError[error.id] = ahora;
        _resaltar(error, ahora);
        _fijar(
          MensajeCoach(TonoMensaje.corrige, error.mensajeCorto,
              detalle: error.mensajeLargo, esExplicacion: true),
          3,
          ahora,
          _retencionExplicacion,
        );
        return _hablar(error.mensajeLargo, ahora, esExplicacion: true);
      }
      _fijar(MensajeCoach(TonoMensaje.corrige, error.mensajeCorto), 1, ahora,
          _retencionVivo);
      final ultimo = _ultimoAvisoPorError[error.id];
      final toca = ultimo == null ||
          ahora.difference(ultimo) >= _repetirAvisoIsometrico;
      if (toca && _puedeHablar(ahora)) {
        _ultimoAvisoPorError[error.id] = ahora;
        return _hablar(error.mensajeCorto, ahora);
      }
      return null;
    }

    // Sin errores: refuerzo si acaba de corregirse.
    final refuerzoLibre = _ultimoRefuerzo == null ||
        ahora.difference(_ultimoRefuerzo!) >= _pausaRefuerzo;
    if (veniaConErrores && refuerzoLibre && _puedeHablar(ahora)) {
      _ultimoRefuerzo = ahora;
      _fijar(const MensajeCoach(TonoMensaje.ok, '¡Eso es!'), 2, ahora,
          _retencionVeredicto);
      return _hablar('¡Eso es, mantén!', ahora);
    }

    // Hitos de tiempo: "15 segundos", "30 segundos"...
    if (e.segundosMantenidos >= _proximoHito && _puedeHablar(ahora)) {
      final tramos = (e.segundosMantenidos / hitoSegundos).floor();
      _proximoHito = (tramos + 1) * hitoSegundos;
      return _hablar('${(tramos * hitoSegundos).round()} segundos', ahora);
    }
    return null;
  }

  // =========================================================================
  // AUXILIARES
  // =========================================================================

  /// Aviso de posición/encuadre: espera 2 s (no molestar por un frame
  /// perdido) y no se repite antes de 8 s.
  Anuncio? _avisoPosicion(DateTime ahora, String texto) {
    final desde = _fueraDesde ??= ahora;
    if (ahora.difference(desde) < _esperaAvisoPosicion) return null;
    final ultimo = _ultimoAvisoPosicion;
    if (ultimo != null && ahora.difference(ultimo) < _repetirAvisoPosicion) {
      return null;
    }
    if (!_puedeHablar(ahora)) return null;
    _ultimoAvisoPosicion = ahora;
    return _hablar(texto, ahora);
  }

  /// Fija un mensaje en pantalla durante [retencion]. Uno de menor
  /// prioridad no puede tapar a uno mayor que siga vigente.
  void _fijar(
      MensajeCoach m, int prioridad, DateTime ahora, Duration retencion) {
    final hasta = _fijadoHasta;
    final vigente = hasta != null && ahora.isBefore(hasta);
    if (vigente && prioridad < _prioridadFijado) return;
    _fijado = m;
    _prioridadFijado = prioridad;
    _fijadoHasta = ahora.add(retencion);
  }

  void _resaltar(ReglaForma regla, DateTime ahora) {
    _resaltadoRep = articulacionesDe(regla);
    _resaltadoHasta = ahora.add(_retencionResaltado);
  }

  bool _puedeHablar(DateTime ahora) {
    final libre = _vozLibreDesde;
    return libre == null || !ahora.isBefore(libre);
  }

  bool _estaExplicando(DateTime ahora) {
    final hasta = _explicandoHasta;
    return hasta != null && ahora.isBefore(hasta);
  }

  /// Registra que se va a hablar y calcula cuándo quedará libre la voz.
  Anuncio _hablar(String texto, DateTime ahora,
      {bool prioritario = false, bool esExplicacion = false}) {
    final duracion = duracionEstimada(texto);
    final pausa = prioritario && !esExplicacion ? pausaVeredicto : pausaVoz;
    _vozLibreDesde = ahora.add(duracion + pausa);
    if (esExplicacion) _explicandoHasta = ahora.add(duracion);
    return Anuncio(texto, prioritario: prioritario);
  }

  /// Aproximación de lo que tarda el TTS en decir [texto]
  /// (~0.35 s por palabra a velocidad normal).
  static Duration duracionEstimada(String texto) {
    final palabras =
        texto.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).length;
    return Duration(milliseconds: 300 + palabras * 350);
  }
}
