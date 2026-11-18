// lib/core/medidor_rendimiento.dart
//
// Fase I.1 — Modo diagnóstico: mide el rendimiento del análisis de cámara.
//
// Es Dart puro (sin Flutter): la pantalla le avisa de cada evento y él
// calcula las cifras. Así se puede probar con un reloj simulado.
//
// Qué mide:
//   - FPS de cámara:   frames que ENTREGA la cámara por segundo.
//   - FPS de análisis: frames que realmente pasan por ML Kit por segundo.
//     (Si la cámara da 30 y se analizan 12, el cuello de botella es ML Kit.)
//   - ms de detección: conversión del frame + ML Kit.
//   - ms de lógica:    motor + coach (nuestro código Dart).
//   - % descartados:   frames que llegaron con ML Kit todavía ocupado.
//
// Dos vistas de los mismos datos:
//   - instantanea(): cifras "en vivo" (último segundo) para el panel.
//   - resumen():     cifras de toda la visita a la pantalla, para el registro
//                    que luego se copia a la planilla (Fases H y J).

import 'dart:collection';

/// Cifras en vivo (último segundo) para el panel de diagnóstico.
class InstantaneaRendimiento {
  final double fpsCamara;
  final double fpsAnalisis;
  final double msDeteccion; // media móvil
  final double msLogica; // media móvil
  final double pctDescartados;

  /// Tamaño del buffer de la cámara (sin rotar), p. ej. 640×480.
  final int? ancho;
  final int? alto;

  const InstantaneaRendimiento({
    required this.fpsCamara,
    required this.fpsAnalisis,
    required this.msDeteccion,
    required this.msLogica,
    required this.pctDescartados,
    this.ancho,
    this.alto,
  });
}

/// Resumen de rendimiento de una visita a la pantalla de entrenamiento.
class ResumenRendimiento {
  /// Segundos con cámara activa (sin contar huecos: cambio de cámara,
  /// segundo plano, guardado).
  final double segundosMedidos;
  final int framesRecibidos;
  final int framesAnalizados;
  final int framesDescartados;
  final double fpsCamaraMedio;
  final double fpsAnalisisMedio;

  /// FPS de análisis del 10 % de segundos más lentos: muestra los "tirones"
  /// mejor que la media.
  final double fpsAnalisisP10;
  final double msDeteccionMedia;

  /// Latencia de detección en los peores casos (percentil 95).
  final double msDeteccionP95;
  final double msLogicaMedia;
  final int? ancho;
  final int? alto;

  const ResumenRendimiento({
    required this.segundosMedidos,
    required this.framesRecibidos,
    required this.framesAnalizados,
    required this.framesDescartados,
    required this.fpsCamaraMedio,
    required this.fpsAnalisisMedio,
    required this.fpsAnalisisP10,
    required this.msDeteccionMedia,
    required this.msDeteccionP95,
    required this.msLogicaMedia,
    this.ancho,
    this.alto,
  });

  double get pctDescartados => framesRecibidos == 0
      ? 0
      : 100 * framesDescartados / framesRecibidos;

  Map<String, dynamic> toJson() => {
        'segundos': segundosMedidos,
        'recibidos': framesRecibidos,
        'analizados': framesAnalizados,
        'descartados': framesDescartados,
        'fps_camara': fpsCamaraMedio,
        'fps_analisis': fpsAnalisisMedio,
        'fps_p10': fpsAnalisisP10,
        'ms_det': msDeteccionMedia,
        'ms_det_p95': msDeteccionP95,
        'ms_logica': msLogicaMedia,
        'ancho': ancho,
        'alto': alto,
      };

  factory ResumenRendimiento.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    int e(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ResumenRendimiento(
      segundosMedidos: d('segundos'),
      framesRecibidos: e('recibidos'),
      framesAnalizados: e('analizados'),
      framesDescartados: e('descartados'),
      fpsCamaraMedio: d('fps_camara'),
      fpsAnalisisMedio: d('fps_analisis'),
      fpsAnalisisP10: d('fps_p10'),
      msDeteccionMedia: d('ms_det'),
      msDeteccionP95: d('ms_det_p95'),
      msLogicaMedia: d('ms_logica'),
      ancho: (j['ancho'] as num?)?.toInt(),
      alto: (j['alto'] as num?)?.toInt(),
    );
  }
}

/// Acumula los eventos de la cámara y calcula las cifras.
class MedidorRendimiento {
  /// Ventana de las cifras en vivo y largo de cada "tramo" del percentil.
  static const ventana = Duration(seconds: 1);

  /// Un silencio de la cámara más largo que esto es un hueco (cambio de
  /// cámara, segundo plano): no cuenta como tiempo medido.
  static const huecoMaximo = Duration(seconds: 1);

  /// Tope de muestras para el percentil 95 (~11 min a 30 FPS).
  static const maxMuestras = 20000;

  /// Suavizado de los ms del panel (para que se puedan leer).
  static const alfaEma = 0.1;

  // --- En vivo ---
  final ListQueue<DateTime> _recibidosVentana = ListQueue();
  final ListQueue<DateTime> _analizadosVentana = ListQueue();
  double? _emaDeteccion;
  double? _emaLogica;

  // --- Totales de la visita ---
  int _recibidos = 0;
  int _analizados = 0;
  int _descartados = 0;
  DateTime? _ultimoRecibido;
  int _activoMicros = 0;
  double _sumaDeteccion = 0;
  double _sumaLogica = 0;
  final List<double> _muestrasDeteccion = [];

  // --- Tramos de 1 s para el percentil 10 de FPS ---
  DateTime? _inicioTramo;
  int _analizadosTramo = 0;
  final List<double> _fpsPorTramo = [];

  int? _ancho;
  int? _alto;

  /// La cámara entregó un frame (se analice o no).
  void frameRecibido(DateTime t) {
    _recibidos++;
    final ultimo = _ultimoRecibido;
    if (ultimo != null) {
      final hueco = t.difference(ultimo);
      if (hueco < huecoMaximo) {
        _activoMicros += hueco.inMicroseconds;
      } else {
        _inicioTramo = null; // el tramo con hueco no es representativo
      }
    }
    _ultimoRecibido = t;
    _recibidosVentana.addLast(t);
    _purgar(t);
    _avanzarTramo(t);
  }

  /// El frame llegó con ML Kit ocupado y se descartó.
  void frameDescartado() => _descartados++;

  /// Un frame terminó de analizarse.
  void frameAnalizado(
    DateTime t, {
    required double msDeteccion,
    required double msLogica,
  }) {
    _analizados++;
    _analizadosTramo++;
    _analizadosVentana.addLast(t);
    _sumaDeteccion += msDeteccion;
    _sumaLogica += msLogica;
    if (_muestrasDeteccion.length < maxMuestras) {
      _muestrasDeteccion.add(msDeteccion);
    }
    _emaDeteccion = _ema(_emaDeteccion, msDeteccion);
    _emaLogica = _ema(_emaLogica, msLogica);
    _purgar(t);
  }

  /// Tamaño real del buffer que entrega la cámara.
  void tamanoImagen(int ancho, int alto) {
    if (ancho <= 0 || alto <= 0) return;
    _ancho = ancho;
    _alto = alto;
  }

  /// Cifras del último segundo.
  InstantaneaRendimiento instantanea(DateTime ahora) {
    _purgar(ahora);
    final r = _recibidosVentana.length;
    final a = _analizadosVentana.length;
    final segundos = ventana.inMicroseconds / 1e6;
    return InstantaneaRendimiento(
      fpsCamara: r / segundos,
      fpsAnalisis: a / segundos,
      msDeteccion: _emaDeteccion ?? 0,
      msLogica: _emaLogica ?? 0,
      pctDescartados: r == 0 ? 0 : (100 * (r - a) / r).clamp(0, 100).toDouble(),
      ancho: _ancho,
      alto: _alto,
    );
  }

  /// Cifras de toda la visita.
  ResumenRendimiento resumen() {
    final segundos = _activoMicros / 1e6;
    double media(double suma) => _analizados == 0 ? 0 : suma / _analizados;
    return ResumenRendimiento(
      segundosMedidos: segundos,
      framesRecibidos: _recibidos,
      framesAnalizados: _analizados,
      framesDescartados: _descartados,
      fpsCamaraMedio: segundos <= 0 ? 0 : _recibidos / segundos,
      fpsAnalisisMedio: segundos <= 0 ? 0 : _analizados / segundos,
      fpsAnalisisP10: percentil(_fpsPorTramo, 0.10),
      msDeteccionMedia: media(_sumaDeteccion),
      msDeteccionP95: percentil(_muestrasDeteccion, 0.95),
      msLogicaMedia: media(_sumaLogica),
      ancho: _ancho,
      alto: _alto,
    );
  }

  /// Percentil por rango más cercano (p entre 0 y 1). 0 si no hay datos.
  static double percentil(List<double> valores, double p) {
    if (valores.isEmpty) return 0;
    final orden = [...valores]..sort();
    return orden[(p * (orden.length - 1)).round()];
  }

  // ---------------------------------------------------------------------------

  static double _ema(double? previo, double nuevo) =>
      previo == null ? nuevo : previo + alfaEma * (nuevo - previo);

  /// Quita de las ventanas lo que tenga más de 1 s.
  void _purgar(DateTime ahora) {
    final limite = ahora.subtract(ventana);
    while (_recibidosVentana.isNotEmpty &&
        !_recibidosVentana.first.isAfter(limite)) {
      _recibidosVentana.removeFirst();
    }
    while (_analizadosVentana.isNotEmpty &&
        !_analizadosVentana.first.isAfter(limite)) {
      _analizadosVentana.removeFirst();
    }
  }

  /// Cierra el tramo de 1 s si ya se cumplió y guarda sus FPS de análisis.
  void _avanzarTramo(DateTime t) {
    final inicio = _inicioTramo;
    if (inicio == null) {
      _inicioTramo = t;
      _analizadosTramo = 0;
      return;
    }
    final largo = t.difference(inicio);
    if (largo < ventana) return;
    _fpsPorTramo.add(_analizadosTramo * 1e6 / largo.inMicroseconds);
    _inicioTramo = t;
    _analizadosTramo = 0;
  }
}