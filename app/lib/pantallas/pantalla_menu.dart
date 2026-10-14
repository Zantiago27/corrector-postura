// lib/pantallas/pantalla_menu.dart
//
// Menú principal (Fase 5, rediseño SmartForm).
// Saludo + tarjeta de racha (datos reales de Supabase) + tarjetas de
// ejercicio + barra inferior Entrenar/Progreso.
// La lógica de selección de ejercicio es la misma de antes.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/tema.dart';
import '../ejercicios/receta_ejercicio.dart';
import '../ejercicios/sentadilla.dart';
import '../ejercicios/curl_biceps.dart';
import '../ejercicios/plancha.dart';
import '../servicios/servicio_sesiones.dart';
import '../servicios/modelos_sesion.dart';
import 'pantalla_camara.dart';
import 'pantalla_historial.dart';

class PantallaMenu extends StatefulWidget {
  final List<CameraDescription> camaras;
  const PantallaMenu({super.key, required this.camaras});

  @override
  State<PantallaMenu> createState() => _PantallaMenuState();
}

class _PantallaMenuState extends State<PantallaMenu> {
  final _servicio = ServicioSesiones();

  // Ejercicios disponibles. Agregar uno nuevo = una línea aquí.
  List<RecetaEjercicio> get _ejercicios =>
      [recetaSentadilla, recetaCurl, recetaPlancha];

  bool _cargandoStats = true;
  int _racha = 0;
  int _sesionesSemana = 0;
  List<DiaProgreso> _ultimos7 = [];

  @override
  void initState() {
    super.initState();
    _cargarStats();
  }

  /// Carga ligera para la tarjeta de racha. Si falla, simplemente no la
  /// mostramos con números (el menú sigue siendo usable).
  Future<void> _cargarStats() async {
    try {
      final sesiones = await _servicio.listarSesiones();
      final resumen = ResumenProgreso.calcular(sesiones);
      if (!mounted) return;
      setState(() {
        _racha = _calcularRacha(sesiones);
        _sesionesSemana = resumen.sesionesSemana;
        _ultimos7 = resumen.ultimos7Dias;
        _cargandoStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoStats = false);
    }
  }

  /// Racha = días consecutivos (hasta hoy, o ayer si hoy aún no entrena) con
  /// al menos una sesión.
  int _calcularRacha(List<SesionResumen> sesiones) {
    if (sesiones.isEmpty) return 0;
    final dias = sesiones
        .map((s) =>
            DateTime(s.iniciada.year, s.iniciada.month, s.iniciada.day))
        .toSet();
    final ahora = DateTime.now();
    var cursor = DateTime(ahora.year, ahora.month, ahora.day);
    // Si hoy todavía no entrena, la racha puede venir de ayer.
    if (!dias.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int racha = 0;
    while (dias.contains(cursor)) {
      racha++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return racha;
  }

  // --- Datos de presentación por ejercicio ---
  String _grupoPara(String id) {
    switch (id) {
      case 'squat':
        return 'Tren inferior';
      case 'curl':
        return 'Brazos';
      case 'plank':
        return 'Core';
      default:
        return 'General';
    }
  }

  String _descripcionPara(RecetaEjercicio e) =>
      e.tipo == TipoEjercicio.isometrico
          ? 'Mide el tiempo que mantienes la postura'
          : 'Cuenta tus repeticiones y corrige tu forma';

  IconData _iconoPara(String id) {
    switch (id) {
      case 'squat':
        return Icons.accessibility_new_rounded;
      case 'curl':
        return Icons.fitness_center_rounded;
      case 'plank':
        return Icons.airline_seat_flat_rounded;
      default:
        return Icons.sports_gymnastics_rounded;
    }
  }

  String get _nombreUsuario {
    final correo = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (correo.isEmpty) return 'Atleta';
    final local = correo.split('@').first;
    if (local.isEmpty) return 'Atleta';
    return local[0].toUpperCase() + local.substring(1);
  }

  void _abrirEjercicio(RecetaEjercicio receta) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PantallaCamara(camaras: widget.camaras, receta: receta),
    ));
  }

  void _irHistorial() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PantallaHistorial()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Medidas.paddingPantalla, 16, Medidas.paddingPantalla, 24),
          children: [
            _encabezado(),
            const SizedBox(height: 22),
            _tarjetaRacha(),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Elige tu ejercicio',
                    style: Theme.of(context).textTheme.titleLarge),
                Text('${_ejercicios.length} disponibles',
                    style: Tipografia.manrope(12.5,
                        peso: FontWeight.w600, color: Colores.suave)),
              ],
            ),
            const SizedBox(height: 14),
            ..._ejercicios.map(_tarjetaEjercicio),
          ],
        ),
      ),
      bottomNavigationBar: _barraInferior(),
    );
  }

  // --- Encabezado con saludo + avatar ---
  Widget _encabezado() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hola,',
                style: Tipografia.manrope(14,
                    peso: FontWeight.w600, color: Colores.suave)),
            Text('$_nombreUsuario 👋',
                style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Cuenta',
          offset: const Offset(0, 48),
          onSelected: (v) {
            if (v == 'historial') _irHistorial();
            if (v == 'salir') Supabase.instance.client.auth.signOut();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'historial', child: Text('Mi progreso')),
            PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
          ],
          child: Container(
            width: 44,
            height: 44,
            decoration: Componentes.tarjeta(radio: 14),
            alignment: Alignment.center,
            child: Text(_nombreUsuario[0],
                style: Tipografia.sora(15,
                    peso: FontWeight.w800, color: Colores.acento)),
          ),
        ),
      ],
    );
  }

  // --- Tarjeta oscura de racha ---
  Widget _tarjetaRacha() {
    final sinDatos = !_cargandoStats && _racha == 0 && _sesionesSemana == 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: Componentes.tarjetaOscura(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sinDatos ? 'Tu racha' : 'Racha actual',
                    style: Tipografia.manrope(12.5,
                        peso: FontWeight.w600, color: const Color(0xFFA49D92))),
                const SizedBox(height: 3),
                Text(
                  _cargandoStats
                      ? '—'
                      : (sinDatos
                          ? '¡Empieza hoy!'
                          : '$_racha ${_racha == 1 ? "día" : "días"} 🔥'),
                  style: Tipografia.sora(28,
                      peso: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  _cargandoStats
                      ? 'Cargando tu progreso...'
                      : (sinDatos
                          ? 'Haz tu primera sesión'
                          : 'Entrenaste $_sesionesSemana '
                              '${_sesionesSemana == 1 ? "vez" : "veces"} esta semana'),
                  style: Tipografia.manrope(12.5, color: const Color(0xFFA49D92)),
                ),
              ],
            ),
          ),
          if (!_cargandoStats && !sinDatos) _barritasRacha(),
        ],
      ),
    );
  }

  Widget _barritasRacha() {
    // Últimos 5 días como barritas (altura por % de forma de ese día).
    final dias = _ultimos7.length > 5
        ? _ultimos7.sublist(_ultimos7.length - 5)
        : _ultimos7;
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: dias.map((d) {
          final activo = d.porcentaje > 0;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              width: 9,
              height: activo ? (d.porcentaje / 100 * 56).clamp(10, 56) : 14,
              decoration: BoxDecoration(
                color: activo ? Colores.acento : const Color(0xFF3A352F),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- Tarjeta de un ejercicio ---
  Widget _tarjetaEjercicio(RecetaEjercicio e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Medidas.radioTarjeta),
          onTap: () => _abrirEjercicio(e),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: Componentes.tarjeta(),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colores.acentoSuave,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_iconoPara(e.id),
                      color: Colores.acento, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.nombre,
                          style: Tipografia.sora(17, peso: FontWeight.w700)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Componentes.chip(_grupoPara(e.id)),
                          Componentes.chip(
                            e.tipo == TipoEjercicio.isometrico
                                ? 'Isométrico'
                                : 'Dinámico',
                            fondo: const Color(0xFFF1EDE6),
                            color: Colores.suave,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_descripcionPara(e),
                          style:
                              Tipografia.manrope(12.5, color: Colores.suave)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colores.acento,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colores.sobreAcento, size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Barra inferior Entrenar / Progreso ---
  Widget _barraInferior() {
    return Container(
      decoration: const BoxDecoration(
        color: Colores.tarjeta,
        border: Border(top: BorderSide(color: Colores.linea)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _itemNav(Icons.home_rounded, 'Entrenar', activo: true, onTap: () {}),
              _itemNav(Icons.bar_chart_rounded, 'Progreso',
                  activo: false, onTap: _irHistorial),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemNav(IconData icono, String texto,
      {required bool activo, required VoidCallback onTap}) {
    final color = activo ? Colores.acento : const Color(0xFFB4ADA2);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: color, size: 23),
            const SizedBox(height: 4),
            Text(texto,
                style: Tipografia.manrope(11, peso: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}