// lib/servicios/cola_sesiones.dart
//
// Cola LOCAL de sesiones pendientes de subir (Fase F).
//
// Si al terminar un entrenamiento no hay internet (o Supabase falla), la
// sesión se guarda aquí, en el teléfono, y se sube después. El usuario
// nunca pierde un entrenamiento.
//
// Se guarda en shared_preferences como JSON (ya es dependencia del
// proyecto). Para unas decenas de sesiones es suficiente; si algún día
// fueran miles, convendría una base local (sqflite/drift).

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'modelos_sesion.dart';

/// Genera un UUID v4 aleatorio (el formato de los ids de Supabase).
/// Se crea en el teléfono para que un reintento NO duplique la sesión:
/// si la misma sesión llega dos veces, la base de datos la ignora.
String generarUuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Una sesión lista para subir (o esperando a poder subirse).
class SesionPendiente {
  final String id;
  final String userId;
  final String ejercicioId;
  final DateTime iniciada;
  final DateTime finalizada;
  final int repsTotales;
  final int repsCorrectas;
  final int repsIncorrectas;
  final int duracionSegundos;

  /// Eventos ya en el formato de la tabla: {numero_rep, es_correcta, errores}.
  final List<Map<String, dynamic>> eventos;

  /// Cuántas veces falló la subida (las que más fallan van al final).
  final int intentos;

  const SesionPendiente({
    required this.id,
    required this.userId,
    required this.ejercicioId,
    required this.iniciada,
    required this.finalizada,
    required this.repsTotales,
    required this.repsCorrectas,
    required this.repsIncorrectas,
    required this.duracionSegundos,
    required this.eventos,
    this.intentos = 0,
  });

  SesionPendiente conIntento() => SesionPendiente(
        id: id,
        userId: userId,
        ejercicioId: ejercicioId,
        iniciada: iniciada,
        finalizada: finalizada,
        repsTotales: repsTotales,
        repsCorrectas: repsCorrectas,
        repsIncorrectas: repsIncorrectas,
        duracionSegundos: duracionSegundos,
        eventos: eventos,
        intentos: intentos + 1,
      );

  /// Parámetro p_sesion de la función guardar_sesion.
  /// IMPORTANTE: fechas en UTC (con "Z"). Una fecha local sin zona se
  /// guardaría como si fuera UTC y quedaría 5 h corrida en Perú.
  Map<String, dynamic> paramsSesion() => {
        'id': id,
        'ejercicio_id': ejercicioId,
        'iniciada_en': iniciada.toUtc().toIso8601String(),
        'finalizada_en': finalizada.toUtc().toIso8601String(),
        'reps_totales': repsTotales,
        'reps_correctas': repsCorrectas,
        'reps_incorrectas': repsIncorrectas,
        'duracion_segundos': duracionSegundos,
      };

  /// Para mostrarla en el historial mientras no se sube.
  SesionResumen aResumen() => SesionResumen(
        id: id,
        ejercicioId: ejercicioId,
        iniciada: iniciada.toLocal(),
        repsTotales: repsTotales,
        repsCorrectas: repsCorrectas,
        repsIncorrectas: repsIncorrectas,
        duracionSegundos: duracionSegundos,
        pendiente: true,
      );

  List<EventoRep> aEventos() => eventos.map(EventoRep.desdeMapa).toList();

  Map<String, dynamic> toJson() => {
        ...paramsSesion(),
        'user_id': userId,
        'eventos': eventos,
        'intentos': intentos,
      };

  factory SesionPendiente.fromJson(Map<String, dynamic> m) => SesionPendiente(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        ejercicioId: m['ejercicio_id'] as String,
        iniciada: DateTime.parse(m['iniciada_en'] as String),
        finalizada: DateTime.parse(m['finalizada_en'] as String),
        repsTotales: m['reps_totales'] as int,
        repsCorrectas: m['reps_correctas'] as int,
        repsIncorrectas: m['reps_incorrectas'] as int,
        duracionSegundos: m['duracion_segundos'] as int,
        eventos: (m['eventos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        intentos: (m['intentos'] as int?) ?? 0,
      );
}

/// Dónde se guarda el texto de la cola. Se abstrae para poder probar la
/// cola en tests sin tocar el almacenamiento real del teléfono.
abstract class AlmacenCola {
  Future<String?> leer();
  Future<void> escribir(String datos);
}

/// Almacén real: shared_preferences.
class AlmacenPreferencias implements AlmacenCola {
  static const _clave = 'sesiones_pendientes_v1';

  @override
  Future<String?> leer() async =>
      (await SharedPreferences.getInstance()).getString(_clave);

  @override
  Future<void> escribir(String datos) async =>
      (await SharedPreferences.getInstance()).setString(_clave, datos);
}

/// Almacén en memoria (para tests).
class AlmacenMemoria implements AlmacenCola {
  String? _datos;

  @override
  Future<String?> leer() async => _datos;

  @override
  Future<void> escribir(String datos) async => _datos = datos;
}

class ColaSesiones {
  final AlmacenCola _almacen;

  ColaSesiones([AlmacenCola? almacen])
      : _almacen = almacen ?? AlmacenPreferencias();

  // Todas las lecturas-escrituras pasan en fila, una detrás de otra, para
  // que dos pantallas no se pisen al modificar la cola a la vez.
  static Future<void> _fila = Future.value();
  // Si ya hay una sincronización en marcha, no se lanza otra.
  static Future<int>? _sincronizando;

  Future<T> _enFila<T>(Future<T> Function() tarea) {
    final resultado = _fila.then((_) => tarea());
    _fila = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<List<SesionPendiente>> _leer() async {
    final texto = await _almacen.leer();
    if (texto == null || texto.isEmpty) return [];
    final lista = jsonDecode(texto) as List;
    return lista
        .map((e) => SesionPendiente.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _escribir(List<SesionPendiente> lista) =>
      _almacen.escribir(jsonEncode(lista.map((s) => s.toJson()).toList()));

  /// Sesiones pendientes (de un usuario, si se indica).
  Future<List<SesionPendiente>> pendientes({String? userId}) =>
      _enFila(() async {
        final todas = await _leer();
        return userId == null
            ? todas
            : todas.where((s) => s.userId == userId).toList();
      });

  /// Agrega (o reemplaza, si ya existe ese id) una sesión pendiente.
  Future<void> agregar(SesionPendiente sesion) => _enFila(() async {
        final lista = await _leer()
          ..removeWhere((s) => s.id == sesion.id);
        lista.add(sesion);
        await _escribir(lista);
      });

  Future<void> quitar(String id) => _enFila(() async {
        final lista = await _leer()..removeWhere((s) => s.id == id);
        await _escribir(lista);
      });

  /// Intenta subir las pendientes del usuario con [subir].
  ///
  /// - Las que suben bien se quitan de la cola.
  /// - Al primer fallo se detiene (probablemente no hay conexión) y anota
  ///   el intento. Las que más fallan se prueban al final, así una sesión
  ///   "problemática" no bloquea a las demás.
  ///
  /// Devuelve cuántas se subieron.
  Future<int> sincronizar({
    required String userId,
    required Future<void> Function(SesionPendiente sesion) subir,
  }) {
    return _sincronizando ??= _sincronizar(userId, subir)
        .whenComplete(() => _sincronizando = null);
  }

  Future<int> _sincronizar(
    String userId,
    Future<void> Function(SesionPendiente sesion) subir,
  ) async {
    // Orden: menos intentos primero; a igualdad, la más antigua primero.
    // (Se desempata por posición porque List.sort no garantiza estabilidad.)
    final conPosicion = (await pendientes(userId: userId)).asMap().entries
        .toList()
      ..sort((a, b) {
        final porIntentos = a.value.intentos.compareTo(b.value.intentos);
        return porIntentos != 0 ? porIntentos : a.key.compareTo(b.key);
      });
    final lista = conPosicion.map((e) => e.value);
    var subidas = 0;
    for (final sesion in lista) {
      try {
        await subir(sesion);
      } catch (_) {
        await agregar(sesion.conIntento());
        break;
      }
      await quitar(sesion.id);
      subidas++;
    }
    return subidas;
  }
}