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
  Future<void> inicializar({
    double tono = 1.0,
    double velocidad = 0.5,
    String idioma = 'es-MX',
  }) async {
    await _tts.setLanguage(idioma); // 'es-ES' España · 'es-MX' Latinoamérica
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
  Future<void> configurar({double? tono, double? velocidad, String? idioma}) async {
    if (idioma != null) await _tts.setLanguage(idioma);
    if (tono != null) await _tts.setPitch(tono);
    if (velocidad != null) await _tts.setSpeechRate(velocidad);
  }

  /// Dice el mensaje solo si es nuevo o si ya pasó el tiempo de espera.
  /// Corta lo que se esté diciendo. Se usa para mensajes sueltos de la
  /// pantalla ("Comencemos", "Comandos de voz activados").
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

  /// Para el COACH (Fase C). El coach ya decide CUÁNDO hablar (pausas,
  /// una vez por rep, etc.), así que aquí NO hay filtro anti-repetición:
  /// "Baja más" puede decirse en dos reps seguidas si el error se repite.
  ///
  /// - [interrumpir] = true (veredicto de la rep): corta lo que se esté
  ///   diciendo y habla ya.
  /// - [interrumpir] = false (aviso normal): si el TTS sigue hablando, el
  ///   aviso se descarta en vez de cortar. Si el error sigue, el coach
  ///   volverá a avisar.
  Future<void> decirCoach(String texto, {bool interrumpir = false}) async {
    if (_hablando && !interrumpir) return;
    _ultimoMensaje = texto;
    _ultimaVez = DateTime.now();
    if (_hablando) await _tts.stop();
    await _tts.speak(texto);
  }

  /// Anuncia un número de repetición (sin filtro de repetición).
  Future<void> decirNumero(int n) async {
    await _tts.stop();
    await _tts.speak('$n');
  }

  /// Corta en seco lo que se esté diciendo (silenciar, salir, terminar).
  Future<void> callar() => _tts.stop();

  /// Limpia el estado (ej. al reiniciar el conteo).
  void reiniciar() {
    _ultimoMensaje = null;
    _ultimaVez = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> cerrar() => _tts.stop();
}
