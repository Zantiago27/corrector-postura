// lib/ejercicios/instrucciones_ejercicio.dart
//
// Contenido DIDÁCTICO de cada ejercicio (Fase D): cómo colocarse, cómo
// hacerlo y las poses clave para la figura animada del tutorial.
//
// Se mantiene separado de la receta a propósito:
//   - receta_ejercicio.dart  -> lógica (qué medir, qué corregir)
//   - este archivo           -> enseñanza (textos y dibujos)
// "Qué te voy a corregir" NO se escribe aquí: el tutorial lo genera solo a
// partir de las reglas de la receta, así nunca se desincroniza.

import 'dart:ui' show Offset;

import 'figura_pose.dart';

class GuiaEjercicio {
  /// Dónde poner el teléfono y cómo colocarse (fase "Prepárate").
  final List<String> colocacion;

  /// Distancia aproximada al teléfono (se muestra en el dibujo).
  final String distancia;

  /// Pasos para hacer el ejercicio bien (3-4, cortos).
  final List<String> pasos;

  /// Poses clave para animar el movimiento. La PRIMERA es la posición
  /// inicial: también se usa como silueta guía en "Prepárate".
  final List<FiguraPose> posesClave;

  const GuiaEjercicio({
    required this.colocacion,
    required this.distancia,
    required this.pasos,
    required this.posesClave,
  });

  FiguraPose get poseInicial => posesClave.first;
}

// --- Poses clave (caja 1 x 1, la figura mira a la derecha) -----------------

final _sentadillaArriba = FiguraPose.perfil(
  cabeza: const Offset(0.50, 0.12),
  hombro: const Offset(0.50, 0.24),
  codo: const Offset(0.62, 0.25),
  mano: const Offset(0.74, 0.25),
  cadera: const Offset(0.50, 0.52),
  rodilla: const Offset(0.52, 0.72),
  pie: const Offset(0.50, 0.92),
  suelo: 0.94,
);

final _sentadillaAbajo = FiguraPose.perfil(
  cabeza: const Offset(0.49, 0.31),
  hombro: const Offset(0.46, 0.42),
  codo: const Offset(0.58, 0.42),
  mano: const Offset(0.70, 0.42),
  cadera: const Offset(0.36, 0.66),
  rodilla: const Offset(0.58, 0.70),
  pie: const Offset(0.50, 0.92),
  suelo: 0.94,
);

final _curlAbajo = FiguraPose.perfil(
  cabeza: const Offset(0.50, 0.12),
  hombro: const Offset(0.50, 0.24),
  codo: const Offset(0.50, 0.40),
  mano: const Offset(0.52, 0.55),
  cadera: const Offset(0.50, 0.52),
  rodilla: const Offset(0.50, 0.72),
  pie: const Offset(0.50, 0.92),
  suelo: 0.94,
);

final _curlArriba = FiguraPose.perfil(
  cabeza: const Offset(0.50, 0.12),
  hombro: const Offset(0.50, 0.24),
  codo: const Offset(0.50, 0.40),
  mano: const Offset(0.58, 0.27),
  cadera: const Offset(0.50, 0.52),
  rodilla: const Offset(0.50, 0.72),
  pie: const Offset(0.50, 0.92),
  suelo: 0.94,
);

// Plancha: de rodillas -> plancha completa (enseña a "subir" a la posición).
final _planchaRodillas = FiguraPose.perfil(
  cabeza: const Offset(0.90, 0.53),
  hombro: const Offset(0.80, 0.57),
  codo: const Offset(0.80, 0.75),
  mano: const Offset(0.92, 0.75),
  cadera: const Offset(0.52, 0.64),
  rodilla: const Offset(0.34, 0.75),
  pie: const Offset(0.14, 0.74),
  suelo: 0.77,
);

final _planchaCompleta = FiguraPose.perfil(
  cabeza: const Offset(0.90, 0.52),
  hombro: const Offset(0.80, 0.56),
  codo: const Offset(0.80, 0.75),
  mano: const Offset(0.92, 0.75),
  cadera: const Offset(0.52, 0.62),
  rodilla: const Offset(0.32, 0.67),
  pie: const Offset(0.12, 0.72),
  suelo: 0.77,
);

// Flexiones (Fase E): brazos estirados -> pecho cerca del suelo.
// Manos y pies fijos en el suelo; el cuerpo baja recto como una tabla.
final _flexionArriba = FiguraPose.perfil(
  cabeza: const Offset(0.86, 0.46),
  hombro: const Offset(0.76, 0.50),
  codo: const Offset(0.76, 0.64),
  mano: const Offset(0.76, 0.78),
  cadera: const Offset(0.48, 0.62),
  rodilla: const Offset(0.30, 0.70),
  pie: const Offset(0.10, 0.78),
  suelo: 0.80,
);

final _flexionAbajo = FiguraPose.perfil(
  cabeza: const Offset(0.85, 0.65),
  hombro: const Offset(0.74, 0.68),
  codo: const Offset(0.63, 0.75),
  mano: const Offset(0.76, 0.78),
  cadera: const Offset(0.47, 0.72),
  rodilla: const Offset(0.29, 0.75),
  pie: const Offset(0.10, 0.78),
  suelo: 0.80,
);

// Jumping jacks (Fase E): vista DE FRENTE, así que cada lado tiene su punto.
const _jumpingCerrado = FiguraPose({
  ParteFigura.cabeza: Offset(0.50, 0.12),
  ParteFigura.hombroI: Offset(0.42, 0.24),
  ParteFigura.hombroD: Offset(0.58, 0.24),
  ParteFigura.codoI: Offset(0.40, 0.38),
  ParteFigura.codoD: Offset(0.60, 0.38),
  ParteFigura.manoI: Offset(0.40, 0.52),
  ParteFigura.manoD: Offset(0.60, 0.52),
  ParteFigura.caderaI: Offset(0.45, 0.52),
  ParteFigura.caderaD: Offset(0.55, 0.52),
  ParteFigura.rodillaI: Offset(0.45, 0.72),
  ParteFigura.rodillaD: Offset(0.55, 0.72),
  ParteFigura.pieI: Offset(0.45, 0.92),
  ParteFigura.pieD: Offset(0.55, 0.92),
}, suelo: 0.94);

const _jumpingAbierto = FiguraPose({
  ParteFigura.cabeza: Offset(0.50, 0.12),
  ParteFigura.hombroI: Offset(0.42, 0.24),
  ParteFigura.hombroD: Offset(0.58, 0.24),
  ParteFigura.codoI: Offset(0.32, 0.14),
  ParteFigura.codoD: Offset(0.68, 0.14),
  ParteFigura.manoI: Offset(0.40, 0.03),
  ParteFigura.manoD: Offset(0.60, 0.03),
  ParteFigura.caderaI: Offset(0.45, 0.52),
  ParteFigura.caderaD: Offset(0.55, 0.52),
  ParteFigura.rodillaI: Offset(0.37, 0.72),
  ParteFigura.rodillaD: Offset(0.63, 0.72),
  ParteFigura.pieI: Offset(0.29, 0.92),
  ParteFigura.pieD: Offset(0.71, 0.92),
}, suelo: 0.94);

// --- Guías por id de receta ------------------------------------------------

final Map<String, GuiaEjercicio> _guias = {
  'squat': GuiaEjercicio(
    colocacion: const [
      'Apoya el teléfono a la altura de tu cintura',
      'Ponte de perfil, a unos 2 metros',
      'Que se vea tu cuerpo entero, de la cabeza a los pies',
    ],
    distancia: '≈ 2 m',
    pasos: const [
      'Pies al ancho de los hombros, puntas un poco hacia afuera',
      'Lleva la cadera hacia atrás, como si fueras a sentarte',
      'Baja hasta que los muslos queden casi paralelos al suelo',
      'Sube empujando con los talones, con el pecho arriba',
    ],
    posesClave: [_sentadillaArriba, _sentadillaAbajo],
  ),
  'curl': GuiaEjercicio(
    colocacion: const [
      'Apoya el teléfono a la altura de tu pecho',
      'Ponte de perfil, a unos 1,5 metros',
      'Que se vean tu hombro, codo, muñeca y cadera',
    ],
    distancia: '≈ 1,5 m',
    pasos: const [
      'De pie, con el brazo estirado junto al cuerpo',
      'Codo pegado al costado durante todo el movimiento',
      'Sube la mano hasta casi tocar el hombro',
      'Baja despacio hasta estirar el brazo',
    ],
    posesClave: [_curlAbajo, _curlArriba],
  ),
  'plank': GuiaEjercicio(
    colocacion: const [
      'Pon el teléfono en el suelo, en horizontal, a tu lado',
      'Colócate de perfil, a unos 2 metros',
      'Que se vea tu cuerpo entero, de hombros a tobillos',
    ],
    distancia: '≈ 2 m',
    pasos: const [
      'Antebrazos en el suelo, codos bajo los hombros',
      'Estira las piernas y apóyate en las puntas de los pies',
      'Hombros, cadera y tobillos en línea recta',
      'Aprieta abdomen y glúteos, y respira con calma',
    ],
    posesClave: [_planchaRodillas, _planchaCompleta],
  ),
  'pushup': GuiaEjercicio(
    colocacion: const [
      'Pon el teléfono en el suelo, en horizontal, a tu lado',
      'Colócate de perfil, a unos 2 metros',
      'Que se vea tu cuerpo entero, de la cabeza a los pies',
    ],
    distancia: '≈ 2 m',
    pasos: const [
      'Manos bajo los hombros, un poco más abiertas que ellos',
      'Cuerpo recto de la cabeza a los talones, abdomen firme',
      'Baja en unos 2 segundos hasta que el pecho casi toque el suelo',
      'Empuja el suelo hasta estirar los brazos',
    ],
    posesClave: [_flexionArriba, _flexionAbajo],
  ),
  'jumping_jack': GuiaEjercicio(
    colocacion: const [
      'Apoya el teléfono en vertical, a la altura de tu cintura',
      'Ponte de frente, a unos 3 metros',
      'Que se vea todo tu cuerpo, también con los brazos arriba',
    ],
    distancia: '≈ 3 m',
    pasos: const [
      'De pie, pies juntos y brazos pegados al cuerpo',
      'Salta abriendo las piernas y subiendo los brazos',
      'Junta las manos sobre la cabeza',
      'Salta de nuevo para volver a la posición inicial',
    ],
    posesClave: [_jumpingCerrado, _jumpingAbierto],
  ),
};

final _guiaGenerica = GuiaEjercicio(
  colocacion: const [
    'Apoya el teléfono a unos 2 metros',
    'Que se vea todo tu cuerpo',
  ],
  distancia: '≈ 2 m',
  pasos: const ['Sigue las indicaciones de voz'],
  posesClave: [_sentadillaArriba],
);

/// Guía completa de un ejercicio (o una genérica si no hay).
GuiaEjercicio guiaDe(String id) => _guias[id] ?? _guiaGenerica;

/// Compatibilidad con el código anterior: tips de colocación.
List<String> instruccionesDe(String id) => guiaDe(id).colocacion;