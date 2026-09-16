import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../ejercicios/receta_ejercicio.dart';
import 'geometria.dart';
import 'contexto_regla.dart';

/// Fase del movimiento en un ejercicio dinámico.
enum FaseMovimiento { arriba, abajo }

/// Resultado de evaluar un frame.
class EvaluacionFrame {
  final double anguloPrincipal;
  final int repeticiones;
  final FaseMovimiento fase;
  final List<ReglaForma> erroresActivos;

  EvaluacionFrame({
    required this.anguloPrincipal,
    required this.repeticiones,
    required this.fase,
    required this.erroresActivos,
  });
}

/// Motor genérico: interpreta la receta, calcula el ángulo principal
/// y cuenta repeticiones. No conoce ningún ejercicio en concreto.
class MotorEjercicio {
  final RecetaEjercicio receta;

  MotorEjercicio(this.receta);

  int _repeticiones = 0;
  FaseMovimiento _fase = FaseMovimiento.arriba;

  int get repeticiones => _repeticiones;

  void reiniciar() {
    _repeticiones = 0;
    _fase = FaseMovimiento.arriba;
  }

  /// Evalúa una pose y actualiza el conteo.
  /// Devuelve null si faltan puntos para calcular el ángulo.
  EvaluacionFrame? evaluar(Pose pose) {
    final det = receta.deteccionRepeticion;
    final a = punto(pose, det.articulacionA);
    final b = punto(pose, det.articulacionB);
    final c = punto(pose, det.articulacionC);
    if (a == null || b == null || c == null) return null;

    final angulo = calcularAngulo(a, b, c);

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
      
    );
  }
}