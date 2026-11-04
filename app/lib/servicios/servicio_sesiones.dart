import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/motor_ejercicio.dart';
import 'cola_sesiones.dart';
import 'modelos_sesion.dart';

/// Resultado de guardar un entrenamiento.
enum ResultadoGuardado {
  /// Subido a Supabase.
  enLaNube,

  /// Sin conexión (o Supabase falló): quedó guardado en el teléfono y se
  /// subirá solo más adelante.
  pendiente,
}

/// Guarda y consulta las sesiones de entrenamiento en Supabase.
///
/// Fase F:
///   - Guardado ATÓMICO con la función SQL `guardar_sesion` (sesión + reps
///     en una sola transacción: o se guarda todo, o nada).
///   - Id generado en el teléfono: un reintento nunca duplica la sesión.
///   - Si no hay conexión, la sesión va a una cola local y se sube después.
///   - Fechas siempre en UTC.
class ServicioSesiones {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ColaSesiones _cola = ColaSesiones();

  /// Tiempo máximo de espera de una subida (red lenta o inestable).
  static const _tiempoMaximo = Duration(seconds: 10);

  /// Guarda una sesión completa con sus eventos de repetición.
  ///
  /// No lanza error por falta de conexión: en ese caso la deja pendiente
  /// en el teléfono y devuelve [ResultadoGuardado.pendiente].
  Future<ResultadoGuardado> guardarSesion({
    required String ejercicioId,
    required DateTime iniciada,
    required int repsTotales,
    required int repsCorrectas,
    required int repsIncorrectas,
    required int duracionSegundos,
    required List<RepeticionCompletada> repeticiones,
  }) async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) {
      throw StateError('No hay una sesión de usuario iniciada');
    }

    final sesion = SesionPendiente(
      id: generarUuidV4(),
      userId: usuario.id,
      ejercicioId: ejercicioId,
      iniciada: iniciada,
      finalizada: DateTime.now(),
      repsTotales: repsTotales,
      repsCorrectas: repsCorrectas,
      repsIncorrectas: repsIncorrectas,
      duracionSegundos: duracionSegundos,
      eventos: repeticiones
          .map((r) => {
                'numero_rep': r.numero,
                'es_correcta': r.esCorrecta,
                'errores': r.errores,
              })
          .toList(),
    );

    try {
      await _subir(sesion);
    } catch (e) {
      debugPrint('Sin conexión al guardar; queda pendiente: $e');
      await _cola.agregar(sesion);
      return ResultadoGuardado.pendiente;
    }

    // Hay conexión: aprovechamos para subir lo que hubiera quedado
    // pendiente de antes (en segundo plano, sin hacer esperar al usuario).
    unawaited(sincronizarPendientes());
    return ResultadoGuardado.enLaNube;
  }

  /// Sube UNA sesión de forma atómica (función SQL guardar_sesion).
  Future<void> _subir(SesionPendiente sesion) async {
    await _supabase.rpc('guardar_sesion', params: {
      'p_sesion': sesion.paramsSesion(),
      'p_eventos': sesion.eventos,
    }).timeout(_tiempoMaximo);
  }

  /// Intenta subir las sesiones que quedaron en el teléfono.
  /// Nunca lanza error. Devuelve cuántas se subieron.
  Future<int> sincronizarPendientes() async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return 0;
    try {
      return await _cola.sincronizar(userId: usuario.id, subir: _subir);
    } catch (e) {
      debugPrint('No se pudieron sincronizar las pendientes: $e');
      return 0;
    }
  }

  /// Cuántas sesiones del usuario siguen sin subir.
  Future<int> cantidadPendientes() async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return 0;
    return (await _cola.pendientes(userId: usuario.id)).length;
  }

  /// Lee todas las sesiones del usuario actual (RLS ya filtra por user_id),
  /// de la más reciente a la más antigua. Para la lista de historial.
  ///
  /// Antes intenta subir las pendientes, y luego añade las que sigan en el
  /// teléfono (marcadas como `pendiente`), para que la racha y el progreso
  /// las cuenten igual.
  Future<List<SesionResumen>> listarSesiones() async {
    await sincronizarPendientes();

    final filas = await _supabase
        .from('sesiones')
        .select()
        .order('iniciada_en', ascending: false);
    final remotas = (filas as List)
        .map((f) => SesionResumen.desdeMapa(f as Map<String, dynamic>))
        .toList();

    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return remotas;
    final idsRemotos = remotas.map((s) => s.id).toSet();
    final locales = (await _cola.pendientes(userId: usuario.id))
        .where((p) => !idsRemotos.contains(p.id))
        .map((p) => p.aResumen());

    return [...remotas, ...locales]
      ..sort((a, b) => b.iniciada.compareTo(a.iniciada));
  }

  /// Estadísticas agregadas (sesiones de la semana, forma media, 7 días).
  /// Se calculan en el cliente a partir de la lista para no hacer más viajes.
  Future<ResumenProgreso> resumenProgreso() async {
    final sesiones = await listarSesiones();
    return ResumenProgreso.calcular(sesiones);
  }

  /// Eventos (rep por rep) de una sesión concreta. Para la pantalla de Detalle.
  /// Si la sesión aún no se subió, se leen del teléfono.
  Future<List<EventoRep>> eventosDeSesion(String sesionId) async {
    for (final p in await _cola.pendientes()) {
      if (p.id == sesionId) return p.aEventos();
    }
    final filas = await _supabase
        .from('eventos_repeticion')
        .select()
        .eq('sesion_id', sesionId)
        .order('numero_rep', ascending: true);
    return (filas as List)
        .map((f) => EventoRep.desdeMapa(f as Map<String, dynamic>))
        .toList();
  }
}