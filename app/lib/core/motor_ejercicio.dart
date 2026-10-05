import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../ejercicios/receta_ejercicio.dart';
import 'geometria.dart';
import 'contexto_regla.dart';

/// Datos de una repetición que acaba de completarse.
class RepeticionCompletada {
  final int numero;
  final bool esCorrecta;
  final List<String> errores; // ids de las reglas que se rompieron

  RepeticionCompletada({
    required this.numero,
    required this.esCorrecta,
    required this.errores,
  });
}

/// Fase del movimiento en un ejercicio dinámico.
enum FaseMovimiento { arriba, abajo }

/// Resultado de evaluar un frame.
class EvaluacionFrame {
  final double anguloPrincipal;
  final int repeticiones;
  final FaseMovimiento fase;
  final List<ReglaForma> erroresActivos;
  final double segundosMantenidos;
  final bool formaCorrecta;
  final RepeticionCompletada? repCompletada;

  EvaluacionFrame({
    required this.anguloPrincipal,
    required this.repeticiones,
    required this.fase,
    required this.erroresActivos,
    this.segundosMantenidos = 0,
    this.formaCorrecta = true,
    this.repCompletada,
  });
}

/// Motor genérico: interpreta la receta, calcula el ángulo principal
/// y cuenta repeticiones. No conoce ningún ejercicio en concreto.
class MotorEjercicio {
  final RecetaEjercicio receta;

  MotorEjercicio(this.receta);

  int _repeticiones = 0;
  FaseMovimiento _fase = FaseMovimiento.arriba;

  //para plancha
  double _segundosMantenidos = 0;
  DateTime? _ultimoInstante;

  //para guardar datos en session
  final Set<String> _erroresRepActual = {}; // errores durante la rep en curso
  int _repsCorrectas = 0;
  int _repsIncorrectas = 0;

  int get repsCorrectas => _repsCorrectas;
  int get repsIncorrectas => _repsIncorrectas;

  double get segundosMantenidos => _segundosMantenidos;

  int get repeticiones => _repeticiones;

  void reiniciar() {
    _repeticiones = 0;
    _fase = FaseMovimiento.arriba;
    _segundosMantenidos = 0;
    _ultimoInstante = null;
    //reiniciamos datos para sesion
    _repsCorrectas = 0;
    _repsIncorrectas = 0;
    _erroresRepActual.clear();
  }

  /// Evalúa una pose y actualiza el conteo.
  /// Devuelve null si faltan puntos para calcular el ángulo.
  EvaluacionFrame? evaluar(Pose pose) {
    if (receta.tipo == TipoEjercicio.isometrico) {
      return _evaluarIsometrico(pose);
    }
    //protegemos modo dinamico
    final det = receta.deteccionRepeticion;
    if (det == null) return null;

    final a = punto(pose, det.articulacionA);
    final b = punto(pose, det.articulacionB);
    final c = punto(pose, det.articulacionC);
    if (a == null || b == null || c == null) return null;

    /*final angulo = calcularAngulo(a, b, c);

    // Máquina de estados:
    //  arriba -> abajo  : cuando el ángulo baja del umbralAbajo
    //  abajo  -> arriba : cuando sube del umbralArriba  => +1 repetición
    if (_fase == FaseMovimiento.arriba && angulo < det.umbralAbajo) {
      _fase = FaseMovimiento.abajo;
    } else if (_fase == FaseMovimiento.abajo && angulo > det.umbralArriba) {
      _fase = FaseMovimiento.arriba;
      _repeticiones++;
    }

    // Evaluar todas las reglas de forma con el contexto actual.
    final ctx = ContextoRegla(pose: pose, anguloPrincipal: angulo);
    final errores = receta.reglasForma
        .where((regla) => regla.condicion(ctx))
        .toList();

    return EvaluacionFrame(
      anguloPrincipal: angulo,
      repeticiones: _repeticiones,
      fase: _fase,
      erroresActivos: errores,
    );*/
    final angulo = calcularAngulo(a, b, c);

    // Errores activos en este frame.
    final ctx = ContextoRegla(pose: pose, anguloPrincipal: angulo);
    final errores = receta.reglasForma
        .where((regla) => regla.condicion(ctx))
        .toList();
    // Acumulamos los errores de la repetición en curso.
    for (final e in errores) {
      _erroresRepActual.add(e.id);
    }

    // Máquina de estados: cuenta una rep al volver de "abajo" a "arriba".
    RepeticionCompletada? repCompletada;
    if (_fase == FaseMovimiento.arriba && angulo < det.umbralAbajo) {
      _fase = FaseMovimiento.abajo;
    } else if (_fase == FaseMovimiento.abajo && angulo > det.umbralArriba) {
      _fase = FaseMovimiento.arriba;
      _repeticiones++;

      // La rep es correcta si no se rompió ninguna regla durante ella.
      final correcta = _erroresRepActual.isEmpty;
      if (correcta) {
        _repsCorrectas++;
      } else {
        _repsIncorrectas++;
      }
      repCompletada = RepeticionCompletada(
        numero: _repeticiones,
        esCorrecta: correcta,
        errores: _erroresRepActual.toList(),
      );
      _erroresRepActual.clear();
    }

    return EvaluacionFrame(
      anguloPrincipal: angulo,
      repeticiones: _repeticiones,
      fase: _fase,
      erroresActivos: errores,
      repCompletada: repCompletada,
    );
  }

  /// Evalúa un ejercicio isométrico: mide el tiempo en postura correcta.
  EvaluacionFrame _evaluarIsometrico(Pose pose) {
    final ctx = ContextoRegla(pose: pose, anguloPrincipal: 0);
    final errores = receta.reglasForma.where((r) => r.condicion(ctx)).toList();
    final formaCorrecta = errores.isEmpty;

    // El cronómetro solo avanza mientras la postura es correcta.
    final ahora = DateTime.now();
    if (formaCorrecta) {
      if (_ultimoInstante != null) {
        _segundosMantenidos +=
            ahora.difference(_ultimoInstante!).inMilliseconds / 1000.0;
      }
      _ultimoInstante = ahora;
    } else {
      _ultimoInstante = null; // pausa (no borra lo acumulado)
    }

    return EvaluacionFrame(
      anguloPrincipal: 0,
      repeticiones: 0,
      fase: FaseMovimiento.arriba,
      erroresActivos: errores,
      segundosMantenidos: _segundosMantenidos,
      formaCorrecta: formaCorrecta,
    );
  }

  /// Pausa el cronómetro (ej. cuando la persona sale de cuadro).
  void pausar() => _ultimoInstante = null;
}
