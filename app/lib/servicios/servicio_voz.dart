import 'package:flutter_tts/flutter_tts.dart';

/// Envuelve la síntesis de voz (Text-To-Speech).
/// Evita repetir el mismo mensaje muchas veces seguidas y expone si está
/// hablando (útil para pausar el reconocimiento de comandos mientras habla).
class ServicioVoz {
  final FlutterTts _tts = FlutterTts();

  String? _ultimoMensaje;
  DateTime _ultimaVez = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _tiempoEspera = const Duration(seconds: 3);

  /// true mientras el TTS está reproduciendo audio.
  bool _hablando = false;
  bool get hablando => _hablando;

  /// Callbacks opcionales para avisar cuándo empieza y termina de hablar.
  /// El servicio de comandos los usa para no escucharse a sí mismo.
  void Function()? alEmpezarHablar;
  void Function()? alTerminarHablar;

  /// Configura idioma, velocidad y tono. Llamar una vez al inicio.
  /// [tono] y [velocidad] permiten personalizar la voz (ver pantalla de ajustes).
  Future<void> inicializar({double tono = 1.0, double velocidad = 0.5}) async {
    await _tts.setLanguage('es-ES'); // 'es-MX' / 'es-US' para acento latino
    await _tts.setSpeechRate(velocidad); // 0.5 = ritmo natural
    await _tts.setPitch(tono); // 0.5 grave – 2.0 agudo
    await _tts.setVolume(1.0);

    // Hace que speak() complete recién cuando termina de hablar.
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {
      _hablando = true;
      alEmpezarHablar?.call();
    });
    _tts.setCompletionHandler(() {
      _hablando = false;
      alTerminarHablar?.call();
    });
    _tts.setCancelHandler(() {
      _hablando = false;
      alTerminarHablar?.call();
    });
    _tts.setErrorHandler((_) {
      _hablando = false;
      alTerminarHablar?.call();
    });
  }

  /// Cambia tono y velocidad en caliente (desde ajustes).
  Future<void> configurar({double? tono, double? velocidad}) async {
    if (tono != null) await _tts.setPitch(tono);
    if (velocidad != null) await _tts.setSpeechRate(velocidad);
  }

  /// Dice el mensaje solo si es nuevo o si ya pasó el tiempo de espera.
  Future<void> decir(String mensaje) async {
    final ahora = DateTime.now();
    final esNuevo = mensaje != _ultimoMensaje;
    final yaPaso = ahora.difference(_ultimaVez) > _tiempoEspera;
    if (!esNuevo && !yaPaso) return;

    _ultimoMensaje = mensaje;
    _ultimaVez = ahora;
    await _tts.stop();
    await _tts.speak(mensaje);
  }

  /// Anuncia un número de repetición (sin filtro de repetición).
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