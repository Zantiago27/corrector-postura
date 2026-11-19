import 'package:corrector_postura/core/gestor_calidad.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fase I.6: calidad adaptativa. Reloj simulado.
// ---------------------------------------------------------------------------

final _t0 = DateTime(2026, 1, 1);

/// Envía frames analizados a [fps] desde [desde] hasta [hasta] (segundos).
/// Devuelve cuántas veces el gestor pidió bajar la calidad.
int _simular(GestorCalidad g, double fps, double desde, double hasta) {
  var pedidos = 0;
  final paso = 1e6 / fps;
  for (var us = desde * 1e6; us < hasta * 1e6; us += paso) {
    final t = _t0.add(Duration(microseconds: us.round()));
    if (g.frameAnalizado(t)) pedidos++;
  }
  return pedidos;
}

void main() {
  test('teléfono fluido (20 FPS): nunca pide bajar', () {
    final g = GestorCalidad();
    expect(_simular(g, 20, 0, 30), 0);
  });

  test('teléfono lento (8 FPS): pide bajar UNA vez, tras 2 s + 3 s', () {
    final g = GestorCalidad();
    expect(_simular(g, 8, 0, 4.9), 0); // aún calentando / llenando ventana
    expect(_simular(g, 8, 4.9, 6), 1);
    expect(_simular(g, 8, 6, 30), 0); // no insiste
  });

  test('arranque lento y luego fluido: no baja (ignora el calentamiento)', () {
    final g = GestorCalidad();
    _simular(g, 5, 0, 2); // primeros 2 s lentos
    expect(_simular(g, 20, 2, 30), 0);
  });

  test('justo por encima del mínimo (13 FPS): no baja', () {
    final g = GestorCalidad();
    expect(_simular(g, 13, 0, 30), 0);
  });

  test('un bajón corto (1 s a 5 FPS) en una sesión fluida: no baja', () {
    final g = GestorCalidad();
    _simular(g, 20, 0, 10);
    expect(_simular(g, 5, 10, 11), 0);
    expect(_simular(g, 20, 11, 20), 0);
  });

  test('reiniciar (cámara nueva) vuelve a evaluar desde cero', () {
    final g = GestorCalidad();
    expect(_simular(g, 8, 0, 6), 1);
    g.reiniciar();
    expect(_simular(g, 8, 10, 14.9), 0); // nuevo calentamiento
    expect(_simular(g, 8, 14.9, 16), 1);
  });
}