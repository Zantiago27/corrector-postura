// lib/servicios/modelos_sesion.dart
//
// Modelos de LECTURA del historial y pequeños helpers de presentación.
// (El guardado sigue usando RepeticionCompletada del motor; esto es solo
//  para leer lo que ya está en Supabase y mostrarlo.)

/// Nombres legibles por id de ejercicio, para historial y detalle.
const Map<String, String> _nombresEjercicio = {
  'squat': 'Sentadilla',
  'curl': 'Curl de bíceps',
  'plank': 'Plancha',
};

String nombreEjercicio(String id) => _nombresEjercicio[id] ?? id;

/// Segundos -> "m:ss".
String formatearDuracion(int segundos) {
  final m = segundos ~/ 60;
  final s = segundos % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Hora local "HH:mm".
String formatearHora(DateTime f) =>
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

/// "Hoy" / "Ayer" / "13 oct".
String etiquetaFecha(DateTime f) {
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(f.year, f.month, f.day);
  final difDias = hoy.difference(dia).inDays;
  if (difDias == 0) return 'Hoy';
  if (difDias == 1) return 'Ayer';
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  return '${f.day} ${meses[f.month - 1]}';
}

/// 'profundidad_insuficiente' -> 'Profundidad insuficiente'.
String embellecerError(String id) {
  if (id.isEmpty) return id;
  final t = id.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}

/// Resumen de una sesión (una fila de `sesiones`) para la lista de historial.
class SesionResumen {
  final String id;
  final String ejercicioId;
  final DateTime iniciada; // ya convertida a hora local
  final int repsTotales;
  final int repsCorrectas;
  final int repsIncorrectas;
  final int duracionSegundos;

  SesionResumen({
    required this.id,
    required this.ejercicioId,
    required this.iniciada,
    required this.repsTotales,
    required this.repsCorrectas,
    required this.repsIncorrectas,
    required this.duracionSegundos,
  });

  /// Ejercicio por tiempo (ej. plancha): sin reps pero con duración.
  bool get esIsometrico => repsTotales == 0 && duracionSegundos > 0;

  String get nombre => nombreEjercicio(ejercicioId);

  /// % de forma correcta. `null` si no aplica (ejercicio por tiempo sin reps).
  int? get porcentajeForma =>
      repsTotales > 0 ? ((repsCorrectas / repsTotales) * 100).round() : null;

  /// Línea de detalle para la tarjeta del historial.
  String get detalle => esIsometrico
      ? formatearDuracion(duracionSegundos)
      : '$repsTotales reps · ${formatearDuracion(duracionSegundos)}';

  factory SesionResumen.desdeMapa(Map<String, dynamic> m) {
    return SesionResumen(
      id: m['id'] as String,
      ejercicioId: m['ejercicio_id'] as String,
      iniciada: DateTime.parse(m['iniciada_en'] as String).toLocal(),
      repsTotales: (m['reps_totales'] as int?) ?? 0,
      repsCorrectas: (m['reps_correctas'] as int?) ?? 0,
      repsIncorrectas: (m['reps_incorrectas'] as int?) ?? 0,
      duracionSegundos: (m['duracion_segundos'] as int?) ?? 0,
    );
  }
}

/// Un evento de repetición (una fila de `eventos_repeticion`) para el detalle.
class EventoRep {
  final int numero;
  final bool esCorrecta;
  final List<String> errores;

  EventoRep({
    required this.numero,
    required this.esCorrecta,
    required this.errores,
  });

  /// Nota legible por repetición.
  String get nota => esCorrecta
      ? 'Correcta'
      : (errores.isEmpty
          ? 'Incorrecta'
          : errores.map(embellecerError).join(' · '));

  factory EventoRep.desdeMapa(Map<String, dynamic> m) {
    final raw = m['errores'];
    final lista = raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    return EventoRep(
      numero: (m['numero_rep'] as int?) ?? 0,
      esCorrecta: (m['es_correcta'] as bool?) ?? false,
      errores: lista,
    );
  }
}

/// Un día del mini-gráfico semanal.
class DiaProgreso {
  final String etiqueta; // 'L','M','X',...
  final int porcentaje; // 0 = sin sesión ese día
  DiaProgreso(this.etiqueta, this.porcentaje);
}

/// Estadísticas agregadas que se muestran arriba del historial.
/// Se calculan a partir de la lista de sesiones (sin consultas extra).
class ResumenProgreso {
  final int sesionesSemana; // últimos 7 días
  final int formaMedia; // % promedio (solo sesiones con % aplicable)
  final List<DiaProgreso> ultimos7Dias;

  ResumenProgreso({
    required this.sesionesSemana,
    required this.formaMedia,
    required this.ultimos7Dias,
  });

  factory ResumenProgreso.calcular(List<SesionResumen> sesiones) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final hace6 = hoy.subtract(const Duration(days: 6)); // ventana de 7 días

    bool enVentana(SesionResumen s) {
      final d = DateTime(s.iniciada.year, s.iniciada.month, s.iniciada.day);
      return !d.isBefore(hace6);
    }

    final recientes = sesiones.where(enVentana).toList();

    // Forma media: promedio de % sobre las sesiones donde aplica.
    final conPct = sesiones.where((s) => s.porcentajeForma != null).toList();
    final media = conPct.isEmpty
        ? 0
        : (conPct.map((s) => s.porcentajeForma!).reduce((a, b) => a + b) /
                conPct.length)
            .round();

    // 7 días en orden cronológico (hace6 .. hoy), % promedio por día.
    const etiquetas = ['L', 'M', 'X', 'J', 'V', 'S', 'D']; // lunes..domingo
    final dias = <DiaProgreso>[];
    for (int i = 0; i < 7; i++) {
      final dia = hace6.add(Duration(days: i));
      final delDia = sesiones.where((s) {
        final d = DateTime(s.iniciada.year, s.iniciada.month, s.iniciada.day);
        return d == dia && s.porcentajeForma != null;
      }).toList();
      final pct = delDia.isEmpty
          ? 0
          : (delDia.map((s) => s.porcentajeForma!).reduce((a, b) => a + b) /
                  delDia.length)
              .round();
      dias.add(DiaProgreso(etiquetas[dia.weekday - 1], pct));
    }

    return ResumenProgreso(
      sesionesSemana: recientes.length,
      formaMedia: media,
      ultimos7Dias: dias,
    );
  }
}