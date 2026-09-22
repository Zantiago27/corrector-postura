import 'package:flutter_tts/flutter_tts.dart';

/// Envuelve la síntesis de voz (Text-To-Speech).
/// Evita repetir el mismo mensaje muchas veces seguidas.
class ServicioVoz {
  final FlutterTts _tts = FlutterTts();

  String? _ultimoMensaje;
  DateTime _ultimaVez = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _tiempoEspera = const Duration(seconds: 3);

  /// Configura idioma y velocidad. Llamar una vez al inicio.
  Future<void> inicializar() async {
    await _tts.setLanguage('es-ES'); // cámbialo a 'es-MX' o 'es-US' si prefieres acento latino
    await _tts.setSpeechRate(0.5);   // 0.5 = ritmo natural (1.0 es muy rápido)
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  /// Dice el mensaje solo si es nuevo o si ya pasó el tiempo de espera.
  Future<void> decir(String mensaje) async {
    final ahora = DateTime.now();
    final esNuevo = mensaje != _ultimoMensaje;
    final yaPaso = ahora.difference(_ultimaVez) > _tiempoEspera;
    if (!esNuevo && !yaPaso) return; // mismo mensaje reciente -> no repetir

    _ultimoMensaje = mensaje;
    _ultimaVez = ahora;
    await _tts.stop();     // corta lo que esté diciendo
    await _tts.speak(mensaje);
  }

  /// Anuncia un número de repetición (siempre, sin filtro de repetición).
  Future<void> decirNumero(int n) async {
    await _tts.stop();
    await _tts.speak('$n');
  }

  /// Limpia el estado (ej. al reiniciar el conteo).
  void reiniciar() {
    _ultimoMensaje = null;
    _ultimaVez = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> cerrar() => _tts.stop();
}