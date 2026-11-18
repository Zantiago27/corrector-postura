import 'package:corrector_postura/core/medidor_rendimiento.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula la cámara: un frame cada [paso] durante [duracion]. Se analiza
/// uno de cada [analizarCada] (el resto se descarta). Devuelve el instante
/// en que terminó.
DateTime simular(
  MedidorRendimiento m, {
  required DateTime desde,
  required Duration duracion,
  required Duration paso,
  int analizarCada = 1,
  double msDeteccion = 40,
}) {
  final fin = desde.add(duracion);
  var t = desde;
  var i = 0;
  while (t.isBefore(fin)) {
    m.frameRecibido(t);
    if (i % analizarCada == 0) {
      m.frameAnalizado(t, msDeteccion: msDeteccion, msLogica: 1);
    } else {
      m.frameDescartado();
    }
    t = t.add(paso);
    i++;
  }
  return t;
}

void main() {
  final t0 = DateTime(2026, 1, 1);
  const p30fps = Duration(microseconds: 33333);
  const p20fps = Duration(milliseconds: 50);

  test('en vivo: cámara a 30 FPS analizando la mitad → 30 / 15 FPS y 50 %',
      () {
    final m = MedidorRendimiento();
    final fin = simular(m,
        desde: t0,
        duracion: const Duration(seconds: 2),
        paso: p30fps,
        analizarCada: 2);
    final v = m.instantanea(fin.subtract(p30fps));
    expect(v.fpsCamara, closeTo(30, 1.5));
    expect(v.fpsAnalisis, closeTo(15, 1.5));
    expect(v.pctDescartados, closeTo(50, 5));
  });

  test('resumen: el percentil 10 de FPS refleja el segundo más lento', () {
    final m = MedidorRendimiento();
    // 3 s analizando todo (20 FPS) y luego 1 s analizando 1 de cada 4 (5 FPS).
    final t = simular(m,
        desde: t0, duracion: const Duration(seconds: 3), paso: p20fps);
    simular(m,
        desde: t,
        duracion: const Duration(milliseconds: 1050),
        paso: p20fps,
        analizarCada: 4);
    final r = m.resumen();
    expect(r.fpsAnalisisP10, closeTo(5, 0.01));
    expect(r.fpsAnalisisMedio, inInclusiveRange(5, 20));
    expect(r.fpsCamaraMedio, closeTo(20, 1));
  });

  test('un hueco (cambio de cámara) no cuenta como tiempo medido', () {
    final m = MedidorRendimiento();
    simular(m, desde: t0, duracion: const Duration(seconds: 1), paso: p20fps);
    // 3 s sin frames y otro segundo de cámara.
    simular(m,
        desde: t0.add(const Duration(seconds: 4)),
        duracion: const Duration(seconds: 1),
        paso: p20fps);
    final r = m.resumen();
    // 19 intervalos de 50 ms en cada tramo = 0.95 s + 0.95 s.
    expect(r.segundosMedidos, closeTo(1.9, 0.01));
    expect(r.framesRecibidos, 40);
  });

  test('ms de detección: media y percentil 95', () {
    final m = MedidorRendimiento();
    for (var i = 1; i <= 100; i++) {
      final t = t0.add(Duration(milliseconds: 50 * i));
      m.frameRecibido(t);
      m.frameAnalizado(t, msDeteccion: i.toDouble(), msLogica: 2);
    }
    final r = m.resumen();
    expect(r.msDeteccionMedia, closeTo(50.5, 0.01));
    expect(r.msDeteccionP95, 95);
    expect(r.msLogicaMedia, closeTo(2, 0.01));
  });

  test('sin datos todo vale 0 (no divide entre cero)', () {
    expect(MedidorRendimiento.percentil([], 0.5), 0);
    final r = MedidorRendimiento().resumen();
    expect(r.fpsAnalisisP10, 0);
    expect(r.fpsCamaraMedio, 0);
    expect(r.msDeteccionMedia, 0);
    expect(r.pctDescartados, 0);
  });

  test('el resumen sobrevive a JSON (para guardarlo en el teléfono)', () {
    final m = MedidorRendimiento()..tamanoImagen(640, 480);
    simular(m,
        desde: t0,
        duracion: const Duration(seconds: 2),
        paso: p30fps,
        analizarCada: 3);
    final original = m.resumen();
    final copia = ResumenRendimiento.fromJson(original.toJson());
    expect(copia.framesRecibidos, original.framesRecibidos);
    expect(copia.framesDescartados, original.framesDescartados);
    expect(copia.fpsAnalisisP10, original.fpsAnalisisP10);
    expect(copia.ancho, 640);
    expect(copia.alto, 480);
  });
}