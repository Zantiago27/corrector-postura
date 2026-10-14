// lib/servicios/servicio_comandos.dart
//
// Reconocimiento de comandos de voz (Speech-To-Text) con palabras clave.
// Escucha en bucle y, al oír una palabra de una lista, dispara una acción.
//
// Puntos clave del diseño:
//  - Android corta el reconocimiento tras cada pausa de silencio: por eso
//    reiniciamos automáticamente mientras los comandos estén activos.
//  - Mientras el entrenador (TTS) habla, se PAUSA la escucha para no
//    reconocerse a sí mismo. Al terminar de hablar, se reanuda.
//  - Si hay audífonos Bluetooth conectados, el micrófono entra por ellos
//    (lo maneja el sistema); no forzamos el micrófono del teléfono.

import 'package:speech_to_text/speech_to_text.dart';

class ServicioComandos {
  final SpeechToText _stt = SpeechToText();

  bool _disponible = false;
  bool _activo = false; // el usuario activó los comandos
  bool _enPausa = false; // pausado temporalmente (mientras el TTS habla)

  /// Palabras clave que, al detectarse, disparan [_onComando].
  List<String> _palabras = [];
  void Function(String palabra)? _onComando;

  bool get disponible => _disponible;
  bool get activo => _activo;

  /// Inicializa el motor y pide permiso de micrófono. Devuelve si quedó listo.
  Future<bool> inicializar() async {
    _disponible = await _stt.initialize(
      onStatus: _alCambiarEstado,
      onError: (_) => _reintentar(),
    );
    return _disponible;
  }

  /// Comienza a escuchar los [comandos] dados (lista de palabras clave).
  /// Cada vez que se detecta una, llama [alDetectar] con la palabra.
  Future<void> escuchar({
    required List<String> comandos,
    required void Function(String palabra) alDetectar,
  }) async {
    if (!_disponible) return;
    _palabras = comandos.map((p) => p.toLowerCase()).toList();
    _onComando = alDetectar;
    _activo = true;
    _enPausa = false;
    await _arrancar();
  }

  /// Pausa temporal (p. ej. mientras el TTS habla).
  Future<void> pausar() async {
    _enPausa = true;
    if (_stt.isListening) await _stt.stop();
  }

  /// Reanuda tras una pausa temporal.
  Future<void> reanudar() async {
    if (!_activo) return;
    _enPausa = false;
    await _arrancar();
  }

  /// Detiene por completo los comandos (el usuario los desactivó).
  Future<void> detener() async {
    _activo = false;
    _enPausa = false;
    if (_stt.isListening) await _stt.stop();
  }

  Future<void> cerrar() async {
    _activo = false;
    await _stt.stop();
  }

  // --- Interno ---

  Future<void> _arrancar() async {
    if (!_activo || _enPausa || _stt.isListening) return;
    try {
      await _stt.listen(
        onResult: _alResultado,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: 'es_ES',
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // No forzar el micrófono del teléfono: deja que el sistema use
          // los audífonos Bluetooth si están conectados.
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (_) {
      // Si falla el arranque, se reintenta vía onStatus/onError.
    }
  }

  void _alResultado(result) {
    final texto = (result.recognizedWords as String).toLowerCase();
    if (texto.isEmpty) return;
    for (final palabra in _palabras) {
      if (texto.contains(palabra)) {
        _onComando?.call(palabra);
        break;
      }
    }
  }

  void _alCambiarEstado(String estado) {
    // Cuando el reconocimiento termina ('done'/'notListening') y seguimos
    // activos y sin pausa, lo reiniciamos para escuchar en continuo.
    if ((estado == 'done' || estado == 'notListening') &&
        _activo &&
        !_enPausa) {
      _reintentar();
    }
  }

  void _reintentar() {
    if (!_activo || _enPausa) return;
    Future.delayed(const Duration(milliseconds: 300), _arrancar);
  }
}