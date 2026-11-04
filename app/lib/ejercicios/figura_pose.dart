import 'dart:ui' show Offset;

// ---------------------------------------------------------------------------
// FIGURA DE PUNTOS (para tutoriales y silueta guía)
//
// Una "pose de dibujo": dónde va cada parte del cuerpo dentro de una caja
// de 1 x 1 (x hacia la derecha, y hacia abajo). No tiene nada que ver con
// ML Kit: son poses ideales, escritas a mano, para ENSEÑAR el movimiento.
//
// Se guardan como datos (en instrucciones_ejercicio.dart) y la UI las
// anima interpolando entre ellas.
// ---------------------------------------------------------------------------

/// Partes que dibuja la figura. I = izquierda, D = derecha.
enum ParteFigura {
  cabeza,
  hombroI,
  hombroD,
  codoI,
  codoD,
  manoI,
  manoD,
  caderaI,
  caderaD,
  rodillaI,
  rodillaD,
  pieI,
  pieD,
}

class FiguraPose {
  final Map<ParteFigura, Offset> partes;

  /// Altura del suelo (0..1) para dibujar una línea de apoyo. null = sin suelo.
  final double? suelo;

  const FiguraPose(this.partes, {this.suelo});

  /// Pose vista DE PERFIL: los dos lados coinciden, así que basta con
  /// dar un punto por articulación. La figura mira hacia la derecha.
  factory FiguraPose.perfil({
    required Offset cabeza,
    required Offset hombro,
    required Offset codo,
    required Offset mano,
    required Offset cadera,
    required Offset rodilla,
    required Offset pie,
    double? suelo,
  }) {
    return FiguraPose({
      ParteFigura.cabeza: cabeza,
      ParteFigura.hombroI: hombro,
      ParteFigura.hombroD: hombro,
      ParteFigura.codoI: codo,
      ParteFigura.codoD: codo,
      ParteFigura.manoI: mano,
      ParteFigura.manoD: mano,
      ParteFigura.caderaI: cadera,
      ParteFigura.caderaD: cadera,
      ParteFigura.rodillaI: rodilla,
      ParteFigura.rodillaD: rodilla,
      ParteFigura.pieI: pie,
      ParteFigura.pieD: pie,
    }, suelo: suelo);
  }

  Offset? operator [](ParteFigura parte) => partes[parte];

  /// Interpola entre dos poses: t = 0 -> [a], t = 1 -> [b].
  /// Una parte que falte en alguna de las dos se toma de la que la tenga.
  static FiguraPose lerp(FiguraPose a, FiguraPose b, double t) {
    final resultado = <ParteFigura, Offset>{};
    for (final parte in ParteFigura.values) {
      final pa = a.partes[parte], pb = b.partes[parte];
      if (pa != null && pb != null) {
        resultado[parte] = Offset.lerp(pa, pb, t)!;
      } else if (pa != null || pb != null) {
        resultado[parte] = (pa ?? pb)!;
      }
    }
    return FiguraPose(resultado, suelo: a.suelo ?? b.suelo);
  }
}