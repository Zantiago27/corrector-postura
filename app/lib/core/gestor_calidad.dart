// lib/core/gestor_calidad.dart
//
// Fase I.6 — Calidad adaptativa de la cámara.
//
// Decide si conviene bajar la resolución porque el teléfono no alcanza a
// analizar suficientes frames por segundo. Es Dart puro (sin Flutter):
// la pantalla le avisa de cada frame analizado y él responde "baja la
// calidad" UNA sola vez.
//
// Reglas:
//   - Ignora los primeros [calentamiento] (al arrancar siempre va lento).
//   - Mide los FPS de análisis en una ventana de [ventana].
//   - Si quedan por debajo de [fpsMinimo] → pide bajar (una vez).
//   - Nunca pide subir: así la calidad no "rebota" de un lado a otro.

import 'dart:collection';

class GestorCalidad {
  /// Por debajo de esto el conteo y los avisos empiezan a resentirse.
  static const double fpsMinimo = 12;

  static const calentamiento = Duration(seconds: 2);
  static const ventana = Duration(seconds: 3);

  DateTime? _inicio;
  final ListQueue<DateTime> _analizados = ListQueue();
  bool _decidido = false;

  /// FPS de análisis en la última ventana (0 si aún no hay datos).
  double get fpsVentana =>
      _analizados.length / (ventana.inMicroseconds / 1e6);

  /// Registra un frame analizado. Devuelve true UNA sola vez: cuando, tras
  /// el calentamiento, la ventana completa quedó por debajo de [fpsMinimo].
  bool frameAnalizado(DateTime t) {
    if (_decidido) return false;
    final inicio = _inicio ??= t;
    _analizados.addLast(t);
    final limite = t.subtract(ventana);
    while (_analizados.isNotEmpty && !_analizados.first.isAfter(limite)) {
      _analizados.removeFirst();
    }
    // Hace falta el calentamiento + una ventana completa de datos.
    if (t.difference(inicio) < calentamiento + ventana) return false;
    if (fpsVentana < fpsMinimo) {
      _decidido = true;
      return true;
    }
    return false;
  }

  /// Empieza de cero (cámara nueva: otra calidad u otra lente).
  void reiniciar() {
    _inicio = null;
    _analizados.clear();
    _decidido = false;
  }
}