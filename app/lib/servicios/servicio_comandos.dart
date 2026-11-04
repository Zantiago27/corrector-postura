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
//
// Fase G (privacidad): en Android el reconocimiento suele hacerlo el
// servicio de Google, que PUEDE enviar el audio a sus servidores. Con
// [soloDispositivo] = true (por defecto) se pide reconocimiento local; si
// el teléfono no lo tiene para el idioma elegido, se avisa con
// [alFallarEnDispositivo] y NO se pasa a la nube sin permiso del usuario.

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ServicioComandos {
  final SpeechToText _stt = SpeechToText();

  bool _disponible = false;
  bool _activo = false; // el usuario activó los comandos
  bool _enPausa = false; // pausado temporalmente (mientras el TTS habla)

  /// Privacidad: usar solo el reconocimiento del teléfono (ver arriba).
  bool soloDispositivo = true;

  /// Idioma del reconocimiento ('es_ES', 'es_MX'...).
  String localeId = 'es_MX';

  /// Se llama si el teléfono no puede reconocer voz sin internet.
  /// Los comandos quedan desactivados.
  void Function()? alFallarEnDispositivo;

  /// Palabras clave que, al detectarse, disparan [_onComando].
  List<String> _palabras = [];
  void Function(String palabra)? _onComando;

  // Con resultados parciales la misma palabra llega varias veces seguidas
  // ("ter", "termi", "terminar"...): solo disparamos una vez cada 2 s.
  DateTime? _ultimoDisparo;
  static const _antiRebote = Duration(seconds: 2);

  bool get disponible => _disponible;
  bool get activo => _activo;

  /// Inicializa el motor y pide permiso de micrófono. Devuelve si quedó listo.
  Future<bool> inicializar() async {
    _disponible = await _stt.initialize(
      onStatus: _alCambiarEstado,
      onError: _alError,
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
    // Al cambiar de comandos, reiniciamos la escucha para no arrastrar
    // texto reconocido con la lista anterior.
    if (_stt.isListening) await _stt.stop();
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
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          onDevice: soloDispositivo,
          // No forzar el micrófono del teléfono: deja que el sistema use
          // los audífonos Bluetooth si están conectados.
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (_) {
      // Si falla el arranque, se reintenta vía onStatus/onError.
    }
  }

  void _alResultado(SpeechRecognitionResult resultado) {
    final texto = resultado.recognizedWords.toLowerCase();
    if (texto.isEmpty) return;
    for (final palabra in _palabras) {
      if (texto.contains(palabra)) {
        final ahora = DateTime.now();
        final ultimo = _ultimoDisparo;
        if (ultimo != null && ahora.difference(ultimo) < _antiRebote) return;
        _ultimoDisparo = ahora;
        _onComando?.call(palabra);
        return;
      }
    }
  }

  void _alError(SpeechRecognitionError error) {
    // Errores de idioma con soloDispositivo = el teléfono no tiene el
    // reconocimiento local para este idioma. No reintentamos ni pasamos a
    // la nube: desactivamos y avisamos.
    final esDeIdioma = error.errorMsg.contains('language');
    if (soloDispositivo && esDeIdioma) {
      _activo = false;
      alFallarEnDispositivo?.call();
      return;
    }
    // El resto (silencio, "no entendí"...) es normal: volvemos a escuchar.
    _reintentar();
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