// lib/pantallas/pantalla_resumen.dart
//
// Fase 5 — Resumen de sesión (pantalla posterior al entrenamiento).
// Es de SOLO VISUALIZACIÓN: la sesión ya se guardó en Supabase al pulsar
// "Finalizar" en la pantalla de cámara. Aquí celebramos el resultado y
// ofrecemos ir al progreso o repetir el ejercicio.
//
// Se adapta al tipo de ejercicio:
//   - dinámico (sentadilla/curl): anillo de % de forma + reps/correctas/incorrectas.
//   - isométrico (plancha): resalta el tiempo mantenido (no cuenta reps).

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../core/motor_ejercicio.dart';
import '../ejercicios/receta_ejercicio.dart';
import '../servicios/modelos_sesion.dart';
import 'pantalla_camara.dart';
import 'pantalla_historial.dart';

class PantallaResumen extends StatelessWidget {
  final List<CameraDescription> camaras;
  final RecetaEjercicio receta;
  final int repsTotales;
  final int repsCorrectas;
  final int repsIncorrectas;
  final int duracionSegundos;

  /// Repeticiones completadas de la sesión (para calcular los errores más
  /// frecuentes). Puede venir vacía en ejercicios isométricos.
  final List<RepeticionCompletada> repeticiones;

  const PantallaResumen({
    super.key,
    required this.camaras,
    required this.receta,
    required this.repsTotales,
    required this.repsCorrectas,
    required this.repsIncorrectas,
    required this.duracionSegundos,
    this.repeticiones = const [],
  });

  bool get _esIsometrico => receta.tipo == TipoEjercicio.isometrico;

  int get _porcentaje =>
      repsTotales > 0 ? ((repsCorrectas / repsTotales) * 100).round() : 0;

  /// Errores más frecuentes (hasta 3), ordenados por nº de apariciones.
  List<MapEntry<String, int>> get _erroresFrecuentes {
    final conteo = <String, int>{};
    for (final rep in repeticiones) {
      for (final err in rep.errores) {
        conteo[err] = (conteo[err] ?? 0) + 1;
      }
    }
    final lista = conteo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return lista.take(3).toList();
  }

  void _verProgreso(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PantallaHistorial()),
    );
  }

  void _repetir(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PantallaCamara(camaras: camaras, receta: receta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
          children: [
            _encabezado(context),
            const SizedBox(height: 26),
            _tarjetaPrincipal(),
            const SizedBox(height: 16),
            if (!_esIsometrico) ...[
              _tilesReps(),
              const SizedBox(height: 22),
            ],
            if (_erroresFrecuentes.isNotEmpty) ...[
              Text('Errores más frecuentes',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ..._erroresFrecuentes.map(_filaError),
              const SizedBox(height: 26),
            ],
            FilledButton(
              onPressed: () => _verProgreso(context),
              child: const Text('Ver mi progreso'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _repetir(context),
              child: const Text('Repetir ejercicio'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Encabezado (check + títulos) ---
  Widget _encabezado(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: const BoxDecoration(
            color: Colores.okSuave,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colores.ok, size: 32),
        ),
        const SizedBox(height: 12),
        Text('¡Buen trabajo!',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Terminaste tu sesión de ${receta.nombre}.',
            style: Tipografia.manrope(14, color: Colores.suave),
            textAlign: TextAlign.center),
      ],
    );
  }

  // --- Tarjeta oscura principal (anillo % o tiempo) ---
  Widget _tarjetaPrincipal() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: Componentes.tarjetaOscura(radio: 22),
      child: _esIsometrico ? _contenidoTiempo() : _contenidoForma(),
    );
  }

  Widget _contenidoForma() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forma correcta',
                style: Tipografia.manrope(12.5,
                    peso: FontWeight.w600, color: const Color(0xFFA49D92))),
            const SizedBox(height: 4),
            Text('$_porcentaje%',
                style: Tipografia.sora(46,
                    peso: FontWeight.w800, color: Colors.white, altura: 1)),
            const SizedBox(height: 4),
            Text('$repsCorrectas de $repsTotales repeticiones',
                style: Tipografia.manrope(12.5, color: const Color(0xFFA49D92))),
          ],
        ),
        _anillo(),
      ],
    );
  }

  Widget _contenidoTiempo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tiempo en posición',
                style: Tipografia.manrope(12.5,
                    peso: FontWeight.w600, color: const Color(0xFFA49D92))),
            const SizedBox(height: 4),
            Text(formatearDuracion(duracionSegundos),
                style: Tipografia.sora(46,
                    peso: FontWeight.w800, color: Colors.white, altura: 1)),
            const SizedBox(height: 4),
            Text('Mantuviste la posición',
                style: Tipografia.manrope(12.5, color: const Color(0xFFA49D92))),
          ],
        ),
        const Icon(Icons.timer_outlined, color: Colores.acento, size: 54),
      ],
    );
  }

  /// Anillo de progreso (% de forma) con número al centro.
  Widget _anillo() {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: (_porcentaje / 100).clamp(0.0, 1.0),
              strokeWidth: 9,
              backgroundColor: const Color(0xFF3A352F),
              valueColor: const AlwaysStoppedAnimation(Colores.acento),
            ),
          ),
          Text('$_porcentaje%',
              style: Tipografia.sora(15, peso: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }

  // --- Tiles: reps / correctas / a corregir ---
  Widget _tilesReps() {
    return Row(
      children: [
        Expanded(child: _Tile(valor: '$repsTotales', etiqueta: 'Reps')),
        const SizedBox(width: 12),
        Expanded(
            child: _Tile(
                valor: '$repsCorrectas',
                etiqueta: 'Correctas',
                color: Colores.ok)),
        const SizedBox(width: 12),
        Expanded(
            child: _Tile(
                valor: '$repsIncorrectas',
                etiqueta: 'A corregir',
                color: Colores.acento)),
      ],
    );
  }

  // --- Fila de error frecuente ---
  Widget _filaError(MapEntry<String, int> e) {
    final veces = e.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: Componentes.tarjeta(radio: 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colores.acentoSuave,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colores.acento, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(embellecerError(e.key),
                      style: Tipografia.manrope(14, peso: FontWeight.w700)),
                  Text('$veces ${veces == 1 ? "vez" : "veces"} esta sesión',
                      style: Tipografia.manrope(12, color: Colores.suave)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile cuadrado (número grande + etiqueta).
class _Tile extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color color;
  const _Tile({
    required this.valor,
    required this.etiqueta,
    this.color = Colores.tinta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: Componentes.tarjeta(radio: 16),
      child: Column(
        children: [
          Text(valor,
              style: Tipografia.sora(24, peso: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(etiqueta,
              style: Tipografia.manrope(11.5,
                  peso: FontWeight.w600, color: Colores.suave)),
        ],
      ),
    );
  }
}