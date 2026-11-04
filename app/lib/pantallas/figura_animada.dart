import 'package:flutter/material.dart';

import '../config/tema.dart';
import '../ejercicios/figura_pose.dart';

// ---------------------------------------------------------------------------
// Dibujo de la figura de puntos (Fase D).
//   - FiguraEstatica: una pose quieta (silueta guía en "Prepárate").
//   - FiguraAnimada:  recorre las poses clave en bucle (tutorial).
// Mismo estilo que el esqueleto de la cámara: así el usuario reconoce
// en el tutorial lo que luego verá sobre su cuerpo.
// ---------------------------------------------------------------------------

/// Figura en una pose fija.
class FiguraEstatica extends StatelessWidget {
  final FiguraPose pose;
  final Color color;
  final Color colorPuntos;
  final double grosor; // relativo al tamaño (0.03 = 3% del lado)

  const FiguraEstatica({
    super.key,
    required this.pose,
    this.color = Colores.acento,
    this.colorPuntos = Colors.white,
    this.grosor = 0.035,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PintorFigura(
        pose: pose,
        color: color,
        colorPuntos: colorPuntos,
        grosor: grosor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Figura que se mueve entre las [poses] en bucle de ida y vuelta.
/// En cada pose clave hace una breve pausa para que se aprecie.
class FiguraAnimada extends StatefulWidget {
  final List<FiguraPose> poses;
  final Duration duracionTramo; // pausa + movimiento entre dos poses
  final Color color;
  final Color colorPuntos;

  const FiguraAnimada({
    super.key,
    required this.poses,
    this.duracionTramo = const Duration(milliseconds: 1400),
    this.color = Colores.acento,
    this.colorPuntos = Colors.white,
  });

  @override
  State<FiguraAnimada> createState() => _FiguraAnimadaState();
}

class _FiguraAnimadaState extends State<FiguraAnimada>
    with SingleTickerProviderStateMixin {
  /// Fracción de cada tramo que la figura se queda quieta.
  static const _fraccionPausa = 0.35;

  late List<FiguraPose> _ciclo;
  late AnimationController _animacion;

  @override
  void initState() {
    super.initState();
    _ciclo = _armarCiclo(widget.poses);
    _animacion = AnimationController(
      vsync: this,
      duration: widget.duracionTramo * _ciclo.length,
    );
    if (_ciclo.length > 1) _animacion.repeat();
  }

  /// Ida y vuelta: [A, B, C] -> A B C B (y vuelve a A).
  static List<FiguraPose> _armarCiclo(List<FiguraPose> poses) {
    if (poses.length <= 2) return poses;
    return [...poses, ...poses.reversed.toList().sublist(1, poses.length - 1)];
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  FiguraPose _poseActual() {
    if (_ciclo.length == 1) return _ciclo.first;
    final v = _animacion.value * _ciclo.length;
    final i = v.floor() % _ciclo.length;
    final local = v - v.floor();
    final t = local < _fraccionPausa
        ? 0.0
        : Curves.easeInOut
            .transform((local - _fraccionPausa) / (1 - _fraccionPausa));
    return FiguraPose.lerp(_ciclo[i], _ciclo[(i + 1) % _ciclo.length], t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animacion,
      builder: (context, _) => CustomPaint(
        painter: PintorFigura(
          pose: _poseActual(),
          color: widget.color,
          colorPuntos: widget.colorPuntos,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Pinta una FiguraPose centrada en un cuadrado que cabe en el lienzo.
class PintorFigura extends CustomPainter {
  final FiguraPose pose;
  final Color color;
  final Color colorPuntos;
  final double grosor;

  PintorFigura({
    required this.pose,
    required this.color,
    this.colorPuntos = Colors.white,
    this.grosor = 0.035,
  });

  static const _huesos = [
    // Tronco
    (ParteFigura.hombroI, ParteFigura.hombroD),
    (ParteFigura.caderaI, ParteFigura.caderaD),
    (ParteFigura.hombroI, ParteFigura.caderaI),
    (ParteFigura.hombroD, ParteFigura.caderaD),
    // Brazos
    (ParteFigura.hombroI, ParteFigura.codoI),
    (ParteFigura.codoI, ParteFigura.manoI),
    (ParteFigura.hombroD, ParteFigura.codoD),
    (ParteFigura.codoD, ParteFigura.manoD),
    // Piernas
    (ParteFigura.caderaI, ParteFigura.rodillaI),
    (ParteFigura.rodillaI, ParteFigura.pieI),
    (ParteFigura.caderaD, ParteFigura.rodillaD),
    (ParteFigura.rodillaD, ParteFigura.pieD),
  ];

  static const _articulaciones = [
    ParteFigura.hombroI, ParteFigura.hombroD,
    ParteFigura.codoI, ParteFigura.codoD,
    ParteFigura.manoI, ParteFigura.manoD,
    ParteFigura.caderaI, ParteFigura.caderaD,
    ParteFigura.rodillaI, ParteFigura.rodillaD,
    ParteFigura.pieI, ParteFigura.pieD,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Cuadrado centrado: la figura no se deforma con el tamaño del widget.
    final lado = size.shortestSide;
    final origen = Offset((size.width - lado) / 2, (size.height - lado) / 2);
    Offset a(Offset p) => origen + Offset(p.dx * lado, p.dy * lado);

    final pintorHueso = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lado * grosor
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Suelo (ejercicios de piso y de pie).
    final suelo = pose.suelo;
    if (suelo != null) {
      canvas.drawLine(
        a(Offset(0.04, suelo)),
        a(Offset(0.96, suelo)),
        Paint()
          ..strokeWidth = lado * 0.012
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35),
      );
    }

    for (final (p1, p2) in _huesos) {
      final o1 = pose[p1], o2 = pose[p2];
      if (o1 == null || o2 == null) continue;
      canvas.drawLine(a(o1), a(o2), pintorHueso);
    }

    // Cuello: del centro de los hombros a la cabeza.
    final cabeza = pose[ParteFigura.cabeza];
    final hI = pose[ParteFigura.hombroI], hD = pose[ParteFigura.hombroD];
    if (cabeza != null && hI != null && hD != null) {
      final centroHombros = Offset.lerp(hI, hD, 0.5)!;
      canvas.drawLine(a(centroHombros), a(Offset.lerp(centroHombros, cabeza, 0.55)!),
          pintorHueso);
      canvas.drawCircle(a(cabeza), lado * 0.055, Paint()..color = color);
    }

    final relleno = Paint()..color = colorPuntos;
    final borde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lado * 0.01
      ..color = color;
    for (final parte in _articulaciones) {
      final o = pose[parte];
      if (o == null) continue;
      canvas.drawCircle(a(o), lado * 0.018, relleno);
      canvas.drawCircle(a(o), lado * 0.018, borde);
    }
  }

  @override
  bool shouldRepaint(covariant PintorFigura anterior) =>
      anterior.pose != pose ||
      anterior.color != color ||
      anterior.colorPuntos != colorPuntos;
}