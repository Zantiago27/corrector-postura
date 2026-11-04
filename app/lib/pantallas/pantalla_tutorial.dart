// lib/pantallas/pantalla_tutorial.dart
//
// Mini-tutorial antes de cada ejercicio (Fase D). Se muestra SIEMPRE, con
// opción de saltarlo. Tres tarjetas:
//   1. Cómo colocarte      (teléfono, distancia, vista)
//   2. Cómo hacerlo        (figura animada + pasos)
//   3. Qué te voy a corregir (generado desde las reglas de la receta)
// Al terminar (o al saltar) abre la cámara reemplazando esta pantalla, así
// "atrás" desde la cámara vuelve directo al menú.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../ejercicios/instrucciones_ejercicio.dart';
import '../ejercicios/receta_ejercicio.dart';
import 'figura_animada.dart';
import 'pantalla_camara.dart';

class PantallaTutorial extends StatefulWidget {
  final List<CameraDescription> camaras;
  final RecetaEjercicio receta;

  const PantallaTutorial({
    super.key,
    required this.camaras,
    required this.receta,
  });

  @override
  State<PantallaTutorial> createState() => _PantallaTutorialState();
}

class _PantallaTutorialState extends State<PantallaTutorial> {
  static const _totalPaginas = 3;
  final _paginas = PageController();
  int _pagina = 0;

  GuiaEjercicio get _guia => guiaDe(widget.receta.id);
  bool get _esUltima => _pagina == _totalPaginas - 1;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _irACamara() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          PantallaCamara(camaras: widget.camaras, receta: widget.receta),
    ));
  }

  void _siguiente() {
    if (_esUltima) {
      _irACamara();
    } else {
      _paginas.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        child: Column(
          children: [
            _barraSuperior(),
            Expanded(
              child: PageView(
                controller: _paginas,
                onPageChanged: (i) => setState(() => _pagina = i),
                children: [
                  _paginaColocacion(),
                  _paginaComoHacerlo(),
                  _paginaQueCorrijo(),
                ],
              ),
            ),
            _pie(),
          ],
        ),
      ),
    );
  }

  // --- Barra superior: cerrar · nombre · Saltar ---
  Widget _barraSuperior() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.close_rounded, color: Colores.tinta),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.receta.nombre,
              textAlign: TextAlign.center,
              style: Tipografia.sora(16, peso: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _irACamara,
            style: TextButton.styleFrom(foregroundColor: Colores.suave),
            child: Text('Saltar',
                style: Tipografia.manrope(14, peso: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // --- Pie: puntos de progreso + botón ---
  Widget _pie() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Medidas.paddingPantalla, 8, Medidas.paddingPantalla, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _totalPaginas; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _pagina ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _pagina ? Colores.acento : Colores.linea,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _siguiente,
            style: FilledButton.styleFrom(
              backgroundColor: Colores.acento,
              foregroundColor: Colores.sobreAcento,
              minimumSize: const Size.fromHeight(Medidas.alturaBoton),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Medidas.radioBoton),
              ),
            ),
            child: Text(_esUltima ? '¡Entendido, empezar!' : 'Siguiente'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PÁGINAS
  // ===========================================================================

  /// Estructura común: ilustración arriba (tarjeta oscura) + contenido.
  Widget _plantillaPagina({
    required String paso,
    required String titulo,
    required Widget ilustracion,
    required List<Widget> contenido,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Medidas.paddingPantalla, 12, Medidas.paddingPantalla, 12),
      children: [
        Container(
          height: 230,
          padding: const EdgeInsets.all(16),
          decoration: Componentes.tarjetaOscura(),
          child: ilustracion,
        ),
        const SizedBox(height: 20),
        Text(paso,
            style: Tipografia.manrope(12,
                peso: FontWeight.w800, color: Colores.acento)),
        const SizedBox(height: 4),
        Text(titulo, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        ...contenido,
      ],
    );
  }

  // 1) Cómo colocarte
  Widget _paginaColocacion() {
    final r = widget.receta;
    final deFrente = r.vista == VistaCamara.frontal;
    final horizontal = r.orientacion == OrientacionSugerida.horizontal;
    return _plantillaPagina(
      paso: 'PASO 1 DE 3',
      titulo: 'Cómo colocarte',
      ilustracion: _EscenaColocacion(
        guia: _guia,
        telefonoHorizontal: horizontal,
      ),
      contenido: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Componentes.chip(deFrente ? 'De frente' : 'De perfil'),
            Componentes.chip(
              horizontal ? 'Teléfono en horizontal' : 'Teléfono en vertical',
              fondo: const Color(0xFFF1EDE6),
              color: Colores.suave,
            ),
            Componentes.chip(
              _guia.distancia,
              fondo: const Color(0xFFF1EDE6),
              color: Colores.suave,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._guia.colocacion.map(_vineta),
      ],
    );
  }

  // 2) Cómo hacerlo
  Widget _paginaComoHacerlo() {
    return _plantillaPagina(
      paso: 'PASO 2 DE 3',
      titulo: 'Cómo hacerlo',
      ilustracion: FiguraAnimada(poses: _guia.posesClave),
      contenido: [
        for (var i = 0; i < _guia.pasos.length; i++)
          _pasoNumerado(i + 1, _guia.pasos[i]),
      ],
    );
  }

  // 3) Qué te voy a corregir (sale de las reglas de la receta)
  Widget _paginaQueCorrijo() {
    final r = widget.receta;
    final reglas = [...r.reglasForma]
      ..sort((a, b) => a.severidad.index.compareTo(b.severidad.index));
    final nota = r.tipo == TipoEjercicio.isometrico
        ? 'El tiempo solo avanza mientras mantienes una buena postura.'
        : 'Solo cuentan las repeticiones bien hechas. Si algo falla, '
            'te diré cómo corregirlo.';
    return _plantillaPagina(
      paso: 'PASO 3 DE 3',
      titulo: 'Qué te voy a corregir',
      ilustracion: FiguraEstatica(pose: _guia.posesClave.last),
      contenido: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colores.acentoSuave,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: Colores.acento),
              const SizedBox(width: 10),
              Expanded(
                child: Text(nota,
                    style: Tipografia.manrope(13.5,
                        peso: FontWeight.w600, altura: 1.35)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...reglas.map(_tarjetaRegla),
      ],
    );
  }

  // --- Piezas ---

  Widget _vineta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3, right: 10),
            child: Icon(Icons.radio_button_checked,
                color: Colores.acento, size: 14),
          ),
          Expanded(
            child: Text(texto,
                style: Tipografia.manrope(14.5, altura: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _pasoNumerado(int n, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colores.acentoSuave,
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: Tipografia.sora(13,
                    peso: FontWeight.w800, color: Colores.acento)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(texto,
                  style: Tipografia.manrope(14.5, altura: 1.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaRegla(ReglaForma regla) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: Componentes.tarjeta(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colores.acentoSuave,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.record_voice_over_rounded,
                color: Colores.acento, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"${regla.mensajeCorto}"',
                    style: Tipografia.sora(15, peso: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(regla.mensajeLargo,
                    style: Tipografia.manrope(13,
                        color: Colores.suave, altura: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibujo "teléfono · distancia · persona" de la página 1.
class _EscenaColocacion extends StatelessWidget {
  final GuiaEjercicio guia;
  final bool telefonoHorizontal;

  const _EscenaColocacion({
    required this.guia,
    required this.telefonoHorizontal,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Teléfono
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotatedBox(
              quarterTurns: telefonoHorizontal ? 1 : 0,
              child: const Icon(Icons.smartphone_rounded,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: 6),
            Text('Teléfono',
                style: Tipografia.manrope(11,
                    peso: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
        // Distancia
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(guia.distancia,
                  style: Tipografia.sora(15,
                      peso: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 6),
              const SizedBox(
                height: 2,
                width: double.infinity,
                child: CustomPaint(painter: _LineaDiscontinua()),
              ),
            ],
          ),
        ),
        // Persona en la posición inicial
        SizedBox(
          width: 130,
          child: FiguraEstatica(pose: guia.poseInicial),
        ),
      ],
    );
  }
}

class _LineaDiscontinua extends CustomPainter {
  const _LineaDiscontinua();

  @override
  void paint(Canvas canvas, Size size) {
    final pintor = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const trazo = 6.0, hueco = 5.0;
    for (var x = 6.0; x < size.width - 6; x += trazo + hueco) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + trazo).clamp(0, size.width - 6), size.height / 2),
          pintor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}