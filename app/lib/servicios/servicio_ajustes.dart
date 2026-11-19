// lib/servicios/servicio_ajustes.dart
//
// Preferencias del usuario (Fase G), guardadas en el teléfono con
// shared_preferences: voz del entrenador y privacidad del micrófono.
// (El nombre NO va aquí: vive en Supabase, en los metadatos del usuario.)

import 'package:shared_preferences/shared_preferences.dart';

/// Acento de la voz y del reconocimiento.
enum AcentoVoz { espana, latino }

class Ajustes {
  /// Tono de la voz: 0.7 (grave) – 1.3 (aguda). 1.0 = natural.
  final double tono;

  /// Velocidad de la voz: 0.3 (lenta) – 0.7 (rápida). 0.5 = natural.
  final double velocidad;

  final AcentoVoz acento;

  /// Si la voz empieza activada al entrar a entrenar.
  final bool vozActiva;

  /// Privacidad: si es true, los comandos de voz SOLO usan el reconocimiento
  /// del propio teléfono y el audio no se envía a internet. Si el teléfono
  /// no lo soporta, los comandos se desactivan (no se pasa a la nube sin
  /// permiso).
  final bool reconocimientoSoloDispositivo;

  /// Fase I.1: muestra FPS/tiempos en la cámara y guarda un resumen por
  /// sesión en el teléfono (para pruebas de rendimiento).
  final bool modoDiagnostico;

  /// Fase I.6: "Modo rendimiento" (cámara en calidad baja). Lo elige el
  /// usuario o se activa solo si el teléfono no alcanza ~12 FPS.
  final bool calidadReducida;

  const Ajustes({
    this.tono = 1.0,
    this.velocidad = 0.5,
    this.acento = AcentoVoz.latino,
    this.vozActiva = true,
    this.reconocimientoSoloDispositivo = true,
    this.modoDiagnostico = false,
    this.calidadReducida = false,
  });

  /// Idioma para el TTS (flutter_tts).
  String get idiomaVoz => acento == AcentoVoz.espana ? 'es-ES' : 'es-MX';

  /// Idioma para el reconocimiento (speech_to_text).
  String get idiomaReconocimiento =>
      acento == AcentoVoz.espana ? 'es_ES' : 'es_MX';

  Ajustes copyWith({
    double? tono,
    double? velocidad,
    AcentoVoz? acento,
    bool? vozActiva,
    bool? reconocimientoSoloDispositivo,
    bool? modoDiagnostico,
    bool? calidadReducida,
  }) =>
      Ajustes(
        tono: tono ?? this.tono,
        velocidad: velocidad ?? this.velocidad,
        acento: acento ?? this.acento,
        vozActiva: vozActiva ?? this.vozActiva,
        reconocimientoSoloDispositivo:
            reconocimientoSoloDispositivo ?? this.reconocimientoSoloDispositivo,
        modoDiagnostico: modoDiagnostico ?? this.modoDiagnostico,
        calidadReducida: calidadReducida ?? this.calidadReducida,
      );
}

class ServicioAjustes {
  ServicioAjustes._();

  static const _tono = 'ajustes_tono';
  static const _velocidad = 'ajustes_velocidad';
  static const _acento = 'ajustes_acento';
  static const _vozActiva = 'ajustes_voz_activa';
  static const _soloDispositivo = 'ajustes_stt_solo_dispositivo';
  static const _diagnostico = 'ajustes_modo_diagnostico';
  static const _calidadReducida = 'ajustes_calidad_reducida';

  static Future<Ajustes> cargar() async {
    final p = await SharedPreferences.getInstance();
    const def = Ajustes();
    return Ajustes(
      tono: p.getDouble(_tono) ?? def.tono,
      velocidad: p.getDouble(_velocidad) ?? def.velocidad,
      acento: p.getString(_acento) == AcentoVoz.espana.name
          ? AcentoVoz.espana
          : AcentoVoz.latino,
      vozActiva: p.getBool(_vozActiva) ?? def.vozActiva,
      reconocimientoSoloDispositivo:
          p.getBool(_soloDispositivo) ?? def.reconocimientoSoloDispositivo,
      modoDiagnostico: p.getBool(_diagnostico) ?? def.modoDiagnostico,
      calidadReducida: p.getBool(_calidadReducida) ?? def.calidadReducida,
    );
  }

  static Future<void> guardar(Ajustes a) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_tono, a.tono);
    await p.setDouble(_velocidad, a.velocidad);
    await p.setString(_acento, a.acento.name);
    await p.setBool(_vozActiva, a.vozActiva);
    await p.setBool(_soloDispositivo, a.reconocimientoSoloDispositivo);
    await p.setBool(_diagnostico, a.modoDiagnostico);
    await p.setBool(_calidadReducida, a.calidadReducida);
  }
}