// lib/pantallas/pantalla_historial.dart
//
// Fase 4.5 — Historial y progreso.
// Lee de Supabase las sesiones del usuario y muestra:
//   - estadísticas de la semana (nº de sesiones, forma media),
//   - mini-gráfico de % de forma de los últimos 7 días,
//   - lista de sesiones (toca una para ver su detalle).
// Maneja estados de carga, vacío y error (con reintento).

import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../servicios/servicio_sesiones.dart';
import '../servicios/modelos_sesion.dart';
import 'pantalla_detalle_sesion.dart';

class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key});

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  final _servicio = ServicioSesiones();

  bool _cargando = true;
  String? _error;
  List<SesionResumen> _sesiones = [];
  ResumenProgreso? _resumen;

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
      final sesiones = await _servicio.listarSesiones();
      setState(() {
        _sesiones = sesiones;
        _resumen = ResumenProgreso.calcular(sesiones);
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No pudimos cargar tu historial.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(child: _contenido()),
    );
  }

  Widget _contenido() {
    if (_cargando) return const _VistaCargando();
    if (_error != null) return _VistaError(mensaje: _error!, onReintentar: _cargar);
    if (_sesiones.isEmpty) return const _VistaVacia();

    // Con datos: encabezado + stats + gráfico + lista.
    return RefreshIndicator(
      color: Colores.acento,
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            Medidas.paddingPantalla, 24, Medidas.paddingPantalla, 32),
        children: [
          Text('Tu progreso', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text('Cada sesión guardada en tu historial.',
              style: Tipografia.manrope(14, color: Colores.suave)),
          const SizedBox(height: 22),
          _filaStats(),
          const SizedBox(height: 16),
          _tarjetaGrafico(),
          const SizedBox(height: 24),
          Text('Historial', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ..._sesiones.map(_tarjetaSesion),
        ],
      ),
    );
  }

  // --- Stats de la semana ---
  Widget _filaStats() {
    final r = _resumen!;
    return Row(
      children: [
        Expanded(
          child: _CajaStat(
            etiqueta: 'Esta semana',
            valor: '${r.sesionesSemana} '
                '${r.sesionesSemana == 1 ? "sesión" : "sesiones"}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CajaStat(
            etiqueta: 'Forma media',
            valor: '${r.formaMedia}%',
            colorValor: Colores.ok,
          ),
        ),
      ],
    );
  }

  // --- Mini-gráfico de barras de los últimos 7 días ---
  Widget _tarjetaGrafico() {
    final dias = _resumen!.ultimos7Dias;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: Componentes.tarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('% de forma correcta',
                  style: Tipografia.manrope(13, peso: FontWeight.w700)),
              Text('últimos 7 días',
                  style: Tipografia.manrope(12, color: Colores.suave)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dias.map(_barraDia).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraDia(DiaProgreso d) {
    // Altura proporcional al %; color según si hay o no datos y qué tan alto.
    final tieneDatos = d.porcentaje > 0;
    final color = !tieneDatos
        ? const Color(0xFFEEE7DD)
        : (d.porcentaje >= 80 ? Colores.acento : const Color(0xFFD8D2C8));
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Barra: 100% -> ~72px; mínimo visible 4px.
            Container(
              height: tieneDatos ? (d.porcentaje / 100 * 72).clamp(4, 72) : 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 7),
            Text(d.etiqueta,
                style: Tipografia.manrope(10,
                    peso: FontWeight.w700, color: Colores.suave)),
          ],
        ),
      ),
    );
  }

  // --- Tarjeta de una sesión en la lista ---
  Widget _tarjetaSesion(SesionResumen s) {
    final pct = s.porcentajeForma;
    final esBuena = pct == null || pct >= 80;
    final colorPct = esBuena ? Colores.ok : Colores.acento;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PantallaDetalleSesion(sesion: s),
            ));
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: Componentes.tarjeta(radio: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: esBuena ? Colores.okSuave : Colores.acentoSuave,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.fitness_center,
                      color: colorPct, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.nombre,
                          style: Tipografia.sora(15.5, peso: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${etiquetaFecha(s.iniciada)} · ${s.detalle}',
                          style:
                              Tipografia.manrope(12.5, color: Colores.suave)),
                    ],
                  ),
                ),
                if (pct != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$pct%',
                          style: Tipografia.manrope(15,
                              peso: FontWeight.w800, color: colorPct)),
                      Text('forma',
                          style: Tipografia.manrope(11, color: Colores.suave)),
                    ],
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    color: Color(0xFFC9C2B7), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Caja de estadística reutilizable (tarjeta blanca con etiqueta + número).
class _CajaStat extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color colorValor;
  const _CajaStat({
    required this.etiqueta,
    required this.valor,
    this.colorValor = Colores.tinta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Componentes.tarjeta(radio: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: Tipografia.manrope(12, color: Colores.suave)),
          const SizedBox(height: 3),
          Text(valor, style: Tipografia.sora(24, peso: FontWeight.w800, color: colorValor)),
        ],
      ),
    );
  }
}

// --- Estados ---

class _VistaCargando extends StatelessWidget {
  const _VistaCargando();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colores.acento),
    );
  }
}

class _VistaVacia extends StatelessWidget {
  const _VistaVacia();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(
                color: Colores.acentoSuave,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bar_chart_rounded,
                  color: Colores.acento, size: 30),
            ),
            const SizedBox(height: 18),
            Text('Aún no tienes sesiones',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Entrena un ejercicio y tu progreso aparecerá aquí.',
              style: Tipografia.manrope(14, color: Colores.suave),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Ir a entrenar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VistaError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;
  const _VistaError({required this.mensaje, required this.onReintentar});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colores.suave, size: 44),
            const SizedBox(height: 16),
            Text(mensaje,
                style: Tipografia.manrope(15, peso: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}