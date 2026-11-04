import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../core/coach_entrenamiento.dart';

// ---------------------------------------------------------------------------
// Widgets visuales del coaching (Fase C).
//   - BannerCoach:       el único mensaje de feedback visible.
//   - TiraRepeticiones:  ●●○●● historial de la serie.
//   - DestelloVeredicto: borde verde/naranja al terminar cada rep.
// Son widgets "tontos": solo pintan lo que les da el coach.
// ---------------------------------------------------------------------------

/// Banner de feedback. Anima solo cuando el mensaje cambia de verdad
/// (usa MensajeCoach.clave), así no parpadea en cada frame.
class BannerCoach extends StatelessWidget {
  final MensajeCoach mensaje;

  const BannerCoach({super.key, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animacion) => FadeTransition(
        opacity: animacion,
        child: SizeTransition(
          sizeFactor: animacion,
          axisAlignment: 1,
          child: child,
        ),
      ),
      child: _contenido(key: ValueKey(mensaje.clave)),
    );
  }

  Widget _contenido({required Key key}) {
    // Contraste (Fase G): sobre naranja, texto oscuro (6.3:1); sobre verde,
    // un verde más profundo con texto blanco (5.3:1). Con blanco sobre el
    // naranja/verde de marca no se llegaba al mínimo de 4.5:1.
    final (Color fondo, Color texto, IconData icono, String etiqueta) =
        switch (mensaje) {
      MensajeCoach(esExplicacion: true) => (
          Colores.acento,
          Colores.sobreAcento,
          Icons.lightbulb_rounded,
          'CÓMO CORREGIRLO',
        ),
      MensajeCoach(tono: TonoMensaje.corrige) => (
          Colores.acento,
          Colores.sobreAcento,
          Icons.priority_high_rounded,
          'CORRIGE',
        ),
      MensajeCoach(tono: TonoMensaje.ok) => (
          Colores.okFuerte,
          Colors.white,
          Icons.check_rounded,
          'BUENA FORMA',
        ),
      MensajeCoach(tono: TonoMensaje.info) => (
          Colores.oscuro,
          Colors.white,
          Icons.info_outline_rounded,
          'ATENCIÓN',
        ),
    };

    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: mensaje.detalle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: texto.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: texto, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(etiqueta,
                    style: Tipografia.manrope(11,
                        peso: FontWeight.w800,
                        color: texto.withValues(alpha: 0.85))),
                Text(mensaje.titulo,
                    style: Tipografia.sora(17,
                        peso: FontWeight.w700,
                        color: texto,
                        altura: 1.2)),
                if (mensaje.detalle != null) ...[
                  const SizedBox(height: 4),
                  Text(mensaje.detalle!,
                      style: Tipografia.manrope(14,
                          peso: FontWeight.w600,
                          color: texto,
                          altura: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tira de puntos con el resultado de cada rep de la serie:
/// verde = correcta, naranja = a corregir. La última lleva un anillo.
class TiraRepeticiones extends StatelessWidget {
  final List<bool> veredictos;
  final int maxVisibles;

  const TiraRepeticiones({
    super.key,
    required this.veredictos,
    this.maxVisibles = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (veredictos.isEmpty) return const SizedBox(height: 14);
    final ocultas = veredictos.length > maxVisibles
        ? veredictos.length - maxVisibles
        : 0;
    final visibles = veredictos.sublist(ocultas);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ocultas > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('+$ocultas',
                style: Tipografia.manrope(12,
                    peso: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.6))),
          ),
        for (var i = 0; i < visibles.length; i++)
          _punto(visibles[i], esUltima: i == visibles.length - 1),
      ],
    );
  }

  Widget _punto(bool correcta, {required bool esUltima}) {
    final color = correcta ? Colores.ok : Colores.acento;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: esUltima ? 14 : 10,
        height: esUltima ? 14 : 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: esUltima ? Border.all(color: Colors.white, width: 2) : null,
        ),
      ),
    );
  }
}

/// Destello en el borde de la pantalla al terminar una rep.
/// Se dispara cuando cambia [idVeredicto]. No bloquea toques.
class DestelloVeredicto extends StatefulWidget {
  final int idVeredicto;
  final bool correcto;

  const DestelloVeredicto({
    super.key,
    required this.idVeredicto,
    required this.correcto,
  });

  @override
  State<DestelloVeredicto> createState() => _DestelloVeredictoState();
}

class _DestelloVeredictoState extends State<DestelloVeredicto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  // Sube rápido (15%) y se desvanece despacio (85%).
  late final Animation<double> _opacidad = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 0)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 85,
    ),
  ]).animate(_animacion);

  @override
  void didUpdateWidget(covariant DestelloVeredicto anterior) {
    super.didUpdateWidget(anterior);
    if (widget.idVeredicto != anterior.idVeredicto && widget.idVeredicto > 0) {
      _animacion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.correcto ? Colores.ok : Colores.acento;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacidad,
        builder: (context, _) {
          final o = _opacidad.value;
          if (o <= 0) return const SizedBox.expand();
          return Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10 * o),
              border: Border.all(
                color: color.withValues(alpha: 0.9 * o),
                width: 10,
              ),
            ),
          );
        },
      ),
    );
  }
}