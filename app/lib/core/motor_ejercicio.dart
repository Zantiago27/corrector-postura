import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../ejercicios/receta_ejercicio.dart';
import 'contexto_regla.dart';
import 'geometria.dart';
import 'racha.dart';
import 'suavizador_pose.dart';

// Para no romper los imports existentes (pantalla_camara usa FaseMovimiento
// importando este archivo), reexportamos los tipos de la receta.
export '../ejercicios/receta_ejercicio.dart'
    show FaseMovimiento, Severidad, ReglaForma;

/// Datos de una repetición que acaba de completarse.
class RepeticionCompletada {
  final int numero;
  final bool esCorrecta;

  /// ids de las reglas rotas (es lo que se guarda en Supabase).
  final List<String> errores;

  /// Reglas rotas, ordenadas por prioridad (la primera es la más grave).
  final List<ReglaForma> reglasRotas;

  final double duracionSegundos;

  RepeticionCompletada({
    required this.numero,
    required this.esCorrecta,
    required this.errores,
    this.reglasRotas = const [],
    this.duracionSegundos = 0,
  });

  /// El error a comunicar al usuario (null si la rep fue correcta).
  ReglaForma? get errorPrincipal =>
      reglasRotas.isEmpty ? null : reglasRotas.first;
}

/// Resultado de evaluar un frame.
class EvaluacionFrame {
  /// Valor de la métrica principal (en la mayoría de ejercicios, un ángulo).
  final double valorPrincipal;
  final int repeticiones;
  final FaseMovimiento fase;

  /// false si el usuario no está en la posición del ejercicio
  /// (ej. de pie cuando debería estar en plancha).
  final bool enPosicion;

  /// Errores activos ahora mismo, ordenados por prioridad.
  final List<ReglaForma> erroresActivos;

  /// Articulaciones REALES (ya con el lado correcto) a resaltar.
  final Set<PoseLandmarkType> articulacionesConError;

  final double segundosMantenidos;
  final bool formaCorrecta;
  final RepeticionCompletada? repCompletada;

  EvaluacionFrame({
    required this.valorPrincipal,
    required this.repeticiones,
    required this.fase,
    required this.erroresActivos,
    this.enPosicion = true,
    this.articulacionesConError = const {},
    this.segundosMantenidos = 0,
    this.formaCorrecta = true,
    this.repCompletada,
  });

  /// El error a mostrar ahora (null si no hay ninguno).
  ReglaForma? get errorPrincipal =>
      erroresActivos.isEmpty ? null : erroresActivos.first;
}

/// Motor genérico: interpreta la receta, suaviza la pose, cuenta
/// repeticiones con histéresis y evalúa las reglas de forma.
/// No conoce ningún ejercicio en concreto.
class MotorEjercicio {
  final RecetaEjercicio receta;
  final SuavizadorPose _suavizador;

  /// Confianza mínima de ML Kit para considerar visible una articulación.
  static const double umbralVisibilidad = 0.5;

  /// Fase I.5: un cambio de fase se acepta si se mantiene al menos
  /// [confirmacionFase] Y [framesConfirmacion] frames seguidos. Filtra picos
  /// (ruido o un frame mal detectado) igual en cualquier teléfono:
  ///   - 20 FPS: 2 frames (como antes).
  ///   - 30 FPS: 3 frames (un parpadeo de 2 frames ya no cuenta).
  ///   - 10 FPS: 2 frames (no suma retraso).
  static const confirmacionFase = Duration(milliseconds: 50);
  static const int framesConfirmacion = 2;

  /// Ventaja de confianza que necesita el otro lado para cambiar de lado.
  static const double _margenCambioLado = 0.15;

  MotorEjercicio(this.receta, {ParametrosSuavizado? suavizado})
      : _suavizador =
            SuavizadorPose(parametros: suavizado ?? receta.suavizado);

  // --- Conteo ---
  int _repeticiones = 0;
  int _repsCorrectas = 0;
  int _repsIncorrectas = 0;
  FaseMovimiento _fase = FaseMovimiento.reposo;

  // Rachas de cada condición del conteo (Fase I.5: por tiempo).
  final _enReposo = Racha();
  final _fueraReposo = Racha();
  final _enExtremo = Racha();
  final _fueraExtremo = Racha();

  // --- Repetición en curso ---
  DateTime? _inicioRep;
  final Map<String, ReglaForma> _erroresRepActual = {};
  final Map<String, double> _agregadosRep = {};

  // --- Reglas instantáneas: desde cuándo se cumple cada una (Fase I.5) ---
  final Map<String, Racha> _rachasReglas = {};

  // --- Isométricos ---
  double _segundosMantenidos = 0;
  DateTime? _ultimoInstante;

  // --- Lado visible ---
  bool _ladoIzquierdo = false;

  int get repeticiones => _repeticiones;
  int get repsCorrectas => _repsCorrectas;
  int get repsIncorrectas => _repsIncorrectas;
  double get segundosMantenidos => _segundosMantenidos;
  FaseMovimiento get fase => _fase;
  bool get ladoIzquierdo => _ladoIzquierdo;

  /// Empieza una serie desde cero.
  void reiniciar() {
    _repeticiones = 0;
    _repsCorrectas = 0;
    _repsIncorrectas = 0;
    _fase = FaseMovimiento.reposo;
    _segundosMantenidos = 0;
    _descartarRepEnCurso();
    pausar();
  }

  /// Pausa temporal (saliste de cuadro, cambio de cámara, segundo plano).
  /// Conserva el conteo, pero olvida el historial de suavizado y los
  /// contadores de frames para no mezclar datos viejos con nuevos.
  void pausar() {
    _ultimoInstante = null;
    _suavizador.reiniciar();
    _rachasReglas.clear();
    for (final r in [_enReposo, _fueraReposo, _enExtremo, _fueraExtremo]) {
      r.reiniciar();
    }
  }

  // =========================================================================
  // ENCUADRE
  // =========================================================================

  /// ¿Se ven las articulaciones que pide la receta? (fase "Prepárate").
  bool cuerpoEncuadrado(Pose pose) {
    _actualizarLado(pose);
    return _puntosVisibles(pose);
  }

  /// Articulaciones REALES que se exigen (ya con el lado elegido).
  List<PoseLandmarkType> get puntosRequeridosReales =>
      receta.puntosRequeridos.map(_tipoReal).toList();

  /// Articulaciones REALES de una regla (para resaltarlas en el esqueleto).
  Set<PoseLandmarkType> articulacionesDe(ReglaForma regla) =>
      regla.articulaciones.map(_tipoReal).toSet();

  PoseLandmarkType _tipoReal(PoseLandmarkType t) =>
      _ladoIzquierdo ? espejo(t) : t;

  bool _puntosVisibles(Pose pose) {
    for (final t in receta.puntosRequeridos) {
      final lm = pose.landmarks[_tipoReal(t)];
      if (lm == null || lm.likelihood < umbralVisibilidad) return false;
    }
    return true;
  }

  /// En vista lateral elige el lado que mejor se ve. Usa un margen para no
  /// saltar de un lado a otro en cada frame.
  void _actualizarLado(Pose pose) {
    if (!receta.ladoAutomatico) {
      _ladoIzquierdo = false;
      return;
    }
    final derecho = _confianzaMedia(pose, izquierdo: false);
    final izquierdo = _confianzaMedia(pose, izquierdo: true);
    if (!_ladoIzquierdo && izquierdo > derecho + _margenCambioLado) {
      _ladoIzquierdo = true;
    } else if (_ladoIzquierdo && derecho > izquierdo + _margenCambioLado) {
      _ladoIzquierdo = false;
    }
  }

  double _confianzaMedia(Pose pose, {required bool izquierdo}) {
    if (receta.puntosRequeridos.isEmpty) return 0;
    var suma = 0.0;
    for (final t in receta.puntosRequeridos) {
      final real = izquierdo ? espejo(t) : t;
      suma += pose.landmarks[real]?.likelihood ?? 0;
    }
    return suma / receta.puntosRequeridos.length;
  }

  // =========================================================================
  // EVALUACIÓN
  // =========================================================================

  /// Evalúa una pose. Devuelve null si no se ven los puntos necesarios
  /// (la pantalla debe llamar a [pausar] en ese caso).
  /// [instante] permite inyectar el tiempo en los tests.
  EvaluacionFrame? evaluar(Pose poseCruda, {DateTime? instante}) {
    final ahora = instante ?? DateTime.now();
    _actualizarLado(poseCruda);
    if (!_puntosVisibles(poseCruda)) return null;

    final pose = _suavizador.suavizar(poseCruda, ahora);
    final ctx = ContextoRegla(pose: pose, ladoIzquierdo: _ladoIzquierdo);
    final enPosicion = receta.posicionValida?.call(ctx) ?? true;

    if (receta.tipo == TipoEjercicio.isometrico) {
      return _evaluarIsometrico(ctx, enPosicion, ahora);
    }
    return _evaluarDinamico(ctx, enPosicion, ahora);
  }

  // --- Dinámico -------------------------------------------------------------

  EvaluacionFrame? _evaluarDinamico(
      ContextoRegla ctxBase, bool enPosicion, DateTime ahora) {
    final det = receta.deteccionRepeticion;
    if (det == null) return null;
    final valor = det.metrica(ctxBase);
    if (valor == null) return null;
    final ctx = ctxBase.conValor(valor);

    if (!enPosicion) {
      // Fuera de posición: no contamos ni corregimos; la rep en curso se pierde.
      _fase = FaseMovimiento.reposo;
      _descartarRepEnCurso();
      _rachasReglas.clear();
      return EvaluacionFrame(
        valorPrincipal: valor,
        repeticiones: _repeticiones,
        fase: _fase,
        enPosicion: false,
        erroresActivos: const [],
        formaCorrecta: false,
      );
    }

    // 1) Máquina de estados (puede cerrar una repetición).
    final repCompletada = _actualizarFase(det, valor, ahora);

    // 2) Reglas instantáneas de la fase actual.
    final activas = _reglasInstantaneasActivas(ctx, _fase, ahora);

    // 3) Si hay una rep en curso, acumulamos sus datos.
    if (_fase != FaseMovimiento.reposo) {
      for (final r in activas) {
        _erroresRepActual[r.id] = r;
      }
      _acumularMedidas(ctx);
    }

    return EvaluacionFrame(
      valorPrincipal: valor,
      repeticiones: _repeticiones,
      fase: _fase,
      erroresActivos: activas,
      articulacionesConError: _articulacionesDeLista(activas),
      formaCorrecta: activas.isEmpty,
      repCompletada: repCompletada,
    );
  }

  /// Máquina de estados con histéresis y confirmación por tiempo (I.5):
  ///
  ///   reposo --(sale de reposo)--> ida --(llega al extremo)--> extremo
  ///   extremo --(sale del extremo)--> vuelta --(llega a reposo)--> reposo [+1 rep]
  ///
  /// Si en "ida" vuelves al reposo sin llegar al extremo, es un amago: no cuenta.
  RepeticionCompletada? _actualizarFase(
      DeteccionRepeticion det, double valor, DateTime ahora) {
    final enReposo = det.estaEnReposo(valor);
    final enExtremo = det.estaEnExtremo(valor);
    _enReposo.actualizar(enReposo, ahora);
    _fueraReposo.actualizar(!enReposo, ahora);
    _enExtremo.actualizar(enExtremo, ahora);
    _fueraExtremo.actualizar(!enExtremo, ahora);

    // ¿La condición ya se mantuvo lo suficiente?
    bool confirmado(Racha r) => r.confirmada(ahora,
        minimo: confirmacionFase, frames: framesConfirmacion);

    switch (_fase) {
      case FaseMovimiento.reposo:
        if (confirmado(_fueraReposo)) {
          _fase = FaseMovimiento.ida;
          _empezarRep(ahora);
        }
        return null;

      case FaseMovimiento.ida:
        if (confirmado(_enExtremo)) {
          _fase = FaseMovimiento.extremo;
        } else if (confirmado(_enReposo)) {
          _fase = FaseMovimiento.reposo; // amago
          _descartarRepEnCurso();
        }
        return null;

      case FaseMovimiento.extremo:
        if (confirmado(_fueraExtremo)) {
          _fase = FaseMovimiento.vuelta;
        }
        return null;

      case FaseMovimiento.vuelta:
        if (confirmado(_enReposo)) {
          _fase = FaseMovimiento.reposo;
          return _cerrarRep(ahora);
        }
        if (confirmado(_enExtremo)) {
          _fase = FaseMovimiento.extremo; // volvió a bajar
        }
        return null;
    }
  }

  void _empezarRep(DateTime ahora) {
    _descartarRepEnCurso();
    _inicioRep = ahora;
  }

  void _descartarRepEnCurso() {
    _inicioRep = null;
    _erroresRepActual.clear();
    _agregadosRep.clear();
  }

  /// Cierra la repetición: aplica las reglas "al completar" y la clasifica.
  RepeticionCompletada? _cerrarRep(DateTime ahora) {
    final inicio = _inicioRep;
    if (inicio == null) return null;
    final duracion = ahora.difference(inicio).inMilliseconds / 1000.0;

    // Demasiado rápida para ser real: se descarta como ruido.
    if (duracion < receta.duracionMinimaRep) {
      _descartarRepEnCurso();
      return null;
    }

    final rotas = <ReglaForma>[..._erroresRepActual.values];
    for (final regla in receta.reglasForma.where((r) => r.esAlCompletar)) {
      final valor =
          regla.medida == null ? 0.0 : _agregadosRep[regla.id];
      if (valor == null) continue; // la medida nunca se pudo calcular
      final resumen = ResumenRep(valor: valor, duracionSegundos: duracion);
      if (regla.condicionRep!(resumen)) rotas.add(regla);
    }
    _ordenarPorPrioridad(rotas);

    _repeticiones++;
    final correcta = rotas.isEmpty;
    if (correcta) {
      _repsCorrectas++;
    } else {
      _repsIncorrectas++;
    }
    final rep = RepeticionCompletada(
      numero: _repeticiones,
      esCorrecta: correcta,
      errores: rotas.map((r) => r.id).toList(),
      reglasRotas: rotas,
      duracionSegundos: duracion,
    );
    _descartarRepEnCurso();
    return rep;
  }

  /// Guarda el mínimo o el máximo de cada medida "al completar".
  void _acumularMedidas(ContextoRegla ctx) {
    for (final regla in receta.reglasForma) {
      final medida = regla.medida;
      if (!regla.esAlCompletar || medida == null) continue;
      final v = medida(ctx);
      if (v == null) continue;
      final previo = _agregadosRep[regla.id];
      if (previo == null) {
        _agregadosRep[regla.id] = v;
      } else {
        _agregadosRep[regla.id] = regla.agregado == AgregadoRep.minimo
            ? (v < previo ? v : previo)
            : (v > previo ? v : previo);
      }
    }
  }

  // --- Isométrico -----------------------------------------------------------

  /// Mide el tiempo en postura correcta. El cronómetro solo avanza si estás
  /// en posición y sin errores.
  EvaluacionFrame _evaluarIsometrico(
      ContextoRegla ctx, bool enPosicion, DateTime ahora) {
    final activas = enPosicion
        ? _reglasInstantaneasActivas(ctx, null, ahora)
        : <ReglaForma>[];
    if (!enPosicion) _rachasReglas.clear();
    final formaCorrecta = enPosicion && activas.isEmpty;

    if (formaCorrecta) {
      final ultimo = _ultimoInstante;
      if (ultimo != null) {
        _segundosMantenidos += ahora.difference(ultimo).inMilliseconds / 1000.0;
      }
      _ultimoInstante = ahora;
    } else {
      _ultimoInstante = null; // pausa (no borra lo acumulado)
    }

    return EvaluacionFrame(
      valorPrincipal: 0,
      repeticiones: 0,
      fase: FaseMovimiento.reposo,
      enPosicion: enPosicion,
      erroresActivos: activas,
      articulacionesConError: _articulacionesDeLista(activas),
      segundosMantenidos: _segundosMantenidos,
      formaCorrecta: formaCorrecta,
    );
  }

  // --- Reglas instantáneas --------------------------------------------------

  /// Evalúa las reglas instantáneas y devuelve las ACTIVAS, ordenadas por
  /// prioridad. Una regla se activa cuando su condición lleva cumpliéndose
  /// al menos [ReglaForma.msMinimos] (y 2 frames; Fase I.5).
  /// Si [fase] es null (isométricos) se ignora el filtro de fase.
  List<ReglaForma> _reglasInstantaneasActivas(
      ContextoRegla ctx, FaseMovimiento? fase, DateTime ahora) {
    final activas = <ReglaForma>[];
    for (final regla in receta.reglasForma) {
      final condicion = regla.condicion;
      if (regla.esAlCompletar || condicion == null) continue;

      final racha = _rachasReglas.putIfAbsent(regla.id, Racha.new);
      final aplica = fase == null || regla.fases.contains(fase);
      if (!aplica) {
        racha.reiniciar();
        continue;
      }
      racha.actualizar(condicion(ctx), ahora);
      final confirmada = racha.confirmada(
        ahora,
        minimo: Duration(milliseconds: regla.msMinimos),
        // Con framesMinimos = 1 basta un frame; si no, al menos 2.
        frames: regla.framesMinimos < 2 ? regla.framesMinimos : 2,
      );
      if (confirmada) activas.add(regla);
    }
    _ordenarPorPrioridad(activas);
    return activas;
  }

  /// Ordena por severidad (alta primero) y, a igual severidad, por el orden
  /// en que aparecen en la receta.
  void _ordenarPorPrioridad(List<ReglaForma> reglas) {
    reglas.sort((a, b) {
      final porSeveridad = a.severidad.index.compareTo(b.severidad.index);
      if (porSeveridad != 0) return porSeveridad;
      return receta.reglasForma
          .indexOf(a)
          .compareTo(receta.reglasForma.indexOf(b));
    });
  }

  Set<PoseLandmarkType> _articulacionesDeLista(List<ReglaForma> reglas) => {
        for (final r in reglas) ...articulacionesDe(r),
      };
}