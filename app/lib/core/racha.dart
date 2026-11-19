// lib/core/racha.dart
//
// Fase I.5 — Confirmación por TIEMPO en lugar de "N frames seguidos".
//
// Antes, un cambio de fase o un error se aceptaba tras N frames seguidos.
// Problema: N frames no son el mismo tiempo en todos los teléfonos.
//   - A 10 FPS, 3 frames = 200 ms → los avisos llegan tarde.
//   - A 30 FPS, 2 frames = 67 ms  → un parpadeo de ML Kit ya cuenta.
//
// Una Racha mide desde CUÁNDO se cumple una condición (y en cuántos frames).
// Se confirma cuando lleva al menos un tiempo mínimo Y un mínimo de frames
// (el mínimo de frames evita decidir con una sola imagen si el teléfono va
// muy lento).

/// Cuánto tiempo (y cuántos frames seguidos) lleva cumpliéndose algo.
class Racha {
  DateTime? _desde;
  int _frames = 0;

  int get frames => _frames;

  /// Registra un frame: si [cumple], la racha sigue; si no, se corta.
  void actualizar(bool cumple, DateTime ahora) {
    if (cumple) {
      _desde ??= ahora;
      _frames++;
    } else {
      reiniciar();
    }
  }

  /// ¿Lleva al menos [minimo] de tiempo y [frames] frames seguidos?
  bool confirmada(
    DateTime ahora, {
    required Duration minimo,
    int frames = 2,
  }) {
    final desde = _desde;
    return desde != null &&
        _frames >= frames &&
        ahora.difference(desde) >= minimo;
  }

  void reiniciar() {
    _desde = null;
    _frames = 0;
  }
}