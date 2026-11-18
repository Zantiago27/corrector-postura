// lib/servicios/registro_rendimiento.dart
//
// Fase I.1 — Registro local de rendimiento (modo diagnóstico).
//
// Al salir de la pantalla de entrenamiento con el modo diagnóstico activo,
// se guarda UNA fila con el resumen de rendimiento + datos del teléfono.
// Desde Ajustes se copian todas las filas como tabla (separada por
// tabuladores) para pegarlas directo en la planilla de pruebas.
//
// Decisiones:
//   - Local (shared_preferences), NO en Supabase: son datos técnicos de
//     prueba, no del usuario, y así no hay que tocar la base de datos.
//   - Modelo del teléfono con device_info_plus: evita etiquetas mal escritas
//     cuando se prueba en varios equipos.
//   - Máximo 50 filas: se descartan las más viejas.

import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/medidor_rendimiento.dart';

/// Datos del teléfono (se leen una vez y se recuerdan).
class InfoEquipo {
  final String modelo;
  final String android;
  final int? ramMb;

  const InfoEquipo({required this.modelo, required this.android, this.ramMb});

  static InfoEquipo? _cache;

  static Future<InfoEquipo> obtener() async {
    final enCache = _cache;
    if (enCache != null) return enCache;
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      return _cache = InfoEquipo(
        modelo: '${a.manufacturer} ${a.model}',
        android: '${a.version.release} (API ${a.version.sdkInt})',
        ramMb: a.physicalRamSize,
      );
    } catch (_) {
      return const InfoEquipo(modelo: 'desconocido', android: '?');
    }
  }
}

/// Una fila del registro.
class RegistroRendimiento {
  final DateTime fecha; // siempre en UTC (regla del proyecto)
  final String equipo;
  final String android;
  final int? ramMb;
  final String ejercicioId;
  final String camara; // 'frontal' / 'trasera' (la última usada)
  final String resolucion; // ResolutionPreset pedido: 'medium', 'low'...
  final ResumenRendimiento resumen;

  const RegistroRendimiento({
    required this.fecha,
    required this.equipo,
    required this.android,
    required this.ejercicioId,
    required this.camara,
    required this.resolucion,
    required this.resumen,
    this.ramMb,
  });

  Map<String, dynamic> toJson() => {
        'fecha': fecha.toUtc().toIso8601String(),
        'equipo': equipo,
        'android': android,
        'ram_mb': ramMb,
        'ejercicio': ejercicioId,
        'camara': camara,
        'resolucion': resolucion,
        'resumen': resumen.toJson(),
      };

  factory RegistroRendimiento.fromJson(Map<String, dynamic> j) =>
      RegistroRendimiento(
        fecha: DateTime.parse(j['fecha'] as String),
        equipo: j['equipo'] as String? ?? '',
        android: j['android'] as String? ?? '',
        ramMb: (j['ram_mb'] as num?)?.toInt(),
        ejercicioId: j['ejercicio'] as String? ?? '',
        camara: j['camara'] as String? ?? '',
        resolucion: j['resolucion'] as String? ?? '',
        resumen: ResumenRendimiento.fromJson(
            Map<String, dynamic>.from(j['resumen'] as Map)),
      );

  /// Encabezados de la tabla (mismo orden que [fila]).
  static const columnas = [
    'fecha',
    'equipo',
    'android',
    'ram_mb',
    'ejercicio',
    'camara',
    'resolucion',
    'imagen',
    'segundos',
    'frames_recibidos',
    'frames_analizados',
    'pct_descartados',
    'fps_camara',
    'fps_analisis',
    'fps_analisis_p10',
    'ms_deteccion',
    'ms_deteccion_p95',
    'ms_logica',
  ];

  /// La fila como texto. La fecha va en hora local para leerla fácil.
  List<String> fila() {
    String n(double v) => v.toStringAsFixed(1);
    final r = resumen;
    final local = fecha.toLocal().toIso8601String();
    return [
      local.substring(0, 19).replaceFirst('T', ' '),
      equipo,
      android,
      ramMb?.toString() ?? '',
      ejercicioId,
      camara,
      resolucion,
      r.ancho == null ? '' : '${r.ancho}x${r.alto}',
      n(r.segundosMedidos),
      '${r.framesRecibidos}',
      '${r.framesAnalizados}',
      n(r.pctDescartados),
      n(r.fpsCamaraMedio),
      n(r.fpsAnalisisMedio),
      n(r.fpsAnalisisP10),
      n(r.msDeteccionMedia),
      n(r.msDeteccionP95),
      n(r.msLogicaMedia),
    ];
  }

  /// Tabla separada por tabuladores: al pegarla en Sheets/Excel cada valor
  /// cae en su propia celda.
  static String comoTabla(List<RegistroRendimiento> registros) => [
        columnas.join('\t'),
        for (final r in registros) r.fila().join('\t'),
      ].join('\n');
}

/// Guarda, lista y borra las filas del registro.
class ServicioRegistroRendimiento {
  ServicioRegistroRendimiento._();

  static const _clave = 'diagnostico_registros';
  static const maxRegistros = 50;

  /// Agrega una fila. Nunca lanza: si algo falla, solo se pierde esa fila
  /// de diagnóstico (no debe afectar al entrenamiento).
  static Future<void> agregar({
    required String ejercicioId,
    required String camara,
    required String resolucion,
    required ResumenRendimiento resumen,
  }) async {
    try {
      final equipo = await InfoEquipo.obtener();
      final registro = RegistroRendimiento(
        fecha: DateTime.now().toUtc(),
        equipo: equipo.modelo,
        android: equipo.android,
        ramMb: equipo.ramMb,
        ejercicioId: ejercicioId,
        camara: camara,
        resolucion: resolucion,
        resumen: resumen,
      );
      final p = await SharedPreferences.getInstance();
      final lista = [...?p.getStringList(_clave)];
      lista.add(jsonEncode(registro.toJson()));
      while (lista.length > maxRegistros) {
        lista.removeAt(0);
      }
      await p.setStringList(_clave, lista);
    } catch (_) {
      // Ignorado a propósito (ver comentario arriba).
    }
  }

  /// Todas las filas, de la más vieja a la más nueva. Ignora filas dañadas.
  static Future<List<RegistroRendimiento>> listar() async {
    final p = await SharedPreferences.getInstance();
    final resultado = <RegistroRendimiento>[];
    for (final texto in p.getStringList(_clave) ?? const <String>[]) {
      try {
        resultado.add(RegistroRendimiento.fromJson(
            Map<String, dynamic>.from(jsonDecode(texto) as Map)));
      } catch (_) {
        // fila dañada: se salta
      }
    }
    return resultado;
  }

  static Future<void> borrar() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_clave);
  }
}