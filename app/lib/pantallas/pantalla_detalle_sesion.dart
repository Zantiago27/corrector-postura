// lib/pantallas/pantalla_detalle_sesion.dart
//
// Fase 4.5 — Detalle de una sesión.
// Muestra el resumen de una sesión (reps, correctas, % forma) y, debajo,
// la lista repetición por repetición leída de `eventos_repeticion`.
// Maneja carga y error al traer los eventos.

import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../servicios/servicio_sesiones.dart';
import '../servicios/modelos_sesion.dart';

class PantallaDetalleSesion extends StatefulWidget {
  final SesionResumen sesion;
  const PantallaDetalleSesion({super.key, required this.sesion});

  @override
  State<PantallaDetalleSesion> createState() => _PantallaDetalleSesionState();
}

class _PantallaDetalleSesionState extends State<PantallaDetalleSesion> {
  final _servicio = ServicioSesiones();

  bool _cargando = true;
  String? _error;
  List<EventoRep> _eventos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final eventos = await _servicio.eventosDeSesion(widget.sesion.id);
      setState(() {
        _eventos = eventos;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No pudimos cargar el detalle.';
        _cargando = false;
      });
    }
  }

  /// Conjunto de errores únicos registrados en toda la sesión (para los chips).
  List<String> get _erroresUnicos {
    final set = <String>{};
    for (final ev in _eventos) {
      set.addAll(ev.errores);
    }
    return set.toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Medidas.paddingPantalla, 16, Medidas.paddingPantalla, 32),
          children: [
            // Volver
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                    foregroundColor: Colores.suave,
                    padding: EdgeInsets.zero),
                icon: const Icon(Icons.chevron_left, size: 20),
                label: Text('Historial',
                    style: Tipografia.manrope(14, peso: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),

            // Título + fecha/hora/duración
            Text(s.nombre, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4),
            Text(
              '${etiquetaFecha(s.iniciada)} · ${formatearHora(s.iniciada)} · '
              '${formatearDuracion(s.duracionSegundos)}',
              style: Tipografia.manrope(14, color: Colores.suave),
            ),
            const SizedBox(height: 22),

            // Tres métricas principales
            _filaMetricas(s),
            const SizedBox(height: 24),

            // Repetición por repetición
            Text('Repetición por repetición',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _seccionEventos(),

            // Errores registrados
            if (!_cargando && _error == null && _erroresUnicos.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Errores registrados',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _erroresUnicos
                    .map((e) => Componentes.chip(embellecerError(e)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaMetricas(SesionResumen s) {
    final pct = s.porcentajeForma;
    return Row(
      children: [
        Expanded(
            child: _Metrica(valor: '${s.repsTotales}', etiqueta: 'Reps')),
        const SizedBox(width: 12),
        Expanded(
            child: _Metrica(
                valor: '${s.repsCorrectas}',
                etiqueta: 'Correctas',
                color: Colores.ok)),
        const SizedBox(width: 12),
        Expanded(
            child: _Metrica(
                valor: pct != null ? '$pct%' : '—',
                etiqueta: 'Forma',
                color: Colores.acento)),
      ],
    );
  }

  Widget _seccionEventos() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: Colores.acento)),
      );
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: Componentes.tarjeta(radio: 14),
        child: Row(
          children: [
            Expanded(
                child: Text(_error!,
                    style: Tipografia.manrope(14, color: Colores.suave))),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_eventos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: Componentes.tarjeta(radio: 14),
        child: Text('Esta sesión no registró repeticiones individuales.',
            style: Tipografia.manrope(14, color: Colores.suave)),
      );
    }
    return Column(children: _eventos.map(_filaEvento).toList());
  }

  Widget _filaEvento(EventoRep ev) {
    final color = ev.esCorrecta ? Colores.ok : Colores.acento;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: Componentes.tarjeta(radio: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(ev.esCorrecta ? Icons.check : Icons.close,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 13),
            SizedBox(
              width: 56,
              child: Text('Rep ${ev.numero}',
                  style: Tipografia.manrope(14, peso: FontWeight.w700)),
            ),
            Expanded(
              child: Text(ev.nota,
                  textAlign: TextAlign.right,
                  style: Tipografia.manrope(13, color: Colores.suave)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Métrica cuadrada (número grande + etiqueta) reutilizada en el detalle.
class _Metrica extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color color;
  const _Metrica({
    required this.valor,
    required this.etiqueta,
    this.color = Colores.tinta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: Componentes.tarjeta(radio: 16),
      child: Column(
        children: [
          Text(valor,
              style: Tipografia.sora(23, peso: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(etiqueta,
              style: Tipografia.manrope(11,
                  peso: FontWeight.w600, color: Colores.suave)),
        ],
      ),
    );
  }
}