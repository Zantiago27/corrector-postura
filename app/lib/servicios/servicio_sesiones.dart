import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/motor_ejercicio.dart';
import 'modelos_sesion.dart';

/// Guarda y consulta las sesiones de entrenamiento en Supabase.
class ServicioSesiones {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Guarda una sesión completa con sus eventos de repetición.
  Future<void> guardarSesion({
    required String ejercicioId,
    required DateTime iniciada,
    required int repsTotales,
    required int repsCorrectas,
    required int repsIncorrectas,
    required int duracionSegundos,
    required List<RepeticionCompletada> repeticiones,
  }) async {
    final userId = _supabase.auth.currentUser!.id;

    // 1) Insertar la sesión y recuperar la fila creada (con su id).
    final filaSesion = await _supabase
        .from('sesiones')
        .insert({
          'user_id': userId,
          'ejercicio_id': ejercicioId,
          'iniciada_en': iniciada.toIso8601String(),
          'finalizada_en': DateTime.now().toIso8601String(),
          'reps_totales': repsTotales,
          'reps_correctas': repsCorrectas,
          'reps_incorrectas': repsIncorrectas,
          'duracion_segundos': duracionSegundos,
        })
        .select()
        .single();

    final sesionId = filaSesion['id'] as String;

    // 2) Insertar los eventos de repetición de un solo golpe (si los hay).
    if (repeticiones.isNotEmpty) {
      final eventos = repeticiones
          .map(
            (r) => {
              'sesion_id': sesionId,
              'numero_rep': r.numero,
              'es_correcta': r.esCorrecta,
              'errores': r.errores, // se guarda como jsonb
            },
          )
          .toList();
      await _supabase.from('eventos_repeticion').insert(eventos);
    }
  }

  /// Lee todas las sesiones del usuario actual (RLS ya filtra por user_id),
  /// de la más reciente a la más antigua. Para la lista de historial.
  Future<List<SesionResumen>> listarSesiones() async {
    final filas = await _supabase
        .from('sesiones')
        .select()
        .order('iniciada_en', ascending: false);
    return (filas as List)
        .map((f) => SesionResumen.desdeMapa(f as Map<String, dynamic>))
        .toList();
  }

  /// Estadísticas agregadas (sesiones de la semana, forma media, 7 días).
  /// Se calculan en el cliente a partir de la lista para no hacer más viajes.
  Future<ResumenProgreso> resumenProgreso() async {
    final sesiones = await listarSesiones();
    return ResumenProgreso.calcular(sesiones);
  }

  /// Eventos (rep por rep) de una sesión concreta. Para la pantalla de Detalle.
  Future<List<EventoRep>> eventosDeSesion(String sesionId) async {
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
