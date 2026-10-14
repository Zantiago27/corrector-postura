// lib/ejercicios/instrucciones_ejercicio.dart
//
// Tips de colocación por ejercicio, para la fase "Prepárate" de la cámara.
// Se mantienen aquí (centralizados y por id) para no tocar el motor ni las
// recetas. Si más adelante quieres purismo "enchufable", se pueden mover como
// un campo dentro de RecetaEjercicio sin cambiar la pantalla.

const Map<String, List<String>> _instrucciones = {
  'squat': [
    'Colócate de perfil a la cámara',
    'Que se vean hombro, cadera, rodilla y tobillo',
    'Aléjate hasta verte de cuerpo completo',
  ],
  'curl': [
    'Ponte de frente o de medio perfil',
    'Que se vean hombro, codo y muñeca',
    'Mantén el brazo dentro del cuadro',
  ],
  'plank': [
    'Apoya el teléfono a tu lado, cerca del suelo',
    'Colócate de perfil mostrando todo el cuerpo',
    'Hombro, cadera y tobillo deben verse',
  ],
};

/// Devuelve los tips de un ejercicio (o unos genéricos si no hay específicos).
List<String> instruccionesDe(String id) =>
    _instrucciones[id] ??
    const ['Colócate frente a la cámara', 'Que se vea todo tu cuerpo'];