import 'package:corrector_postura/servicios/cola_sesiones.dart';
import 'package:flutter_test/flutter_test.dart';

SesionPendiente sesion(String id, {String usuario = 'u1', int intentos = 0}) =>
    SesionPendiente(
      id: id,
      userId: usuario,
      ejercicioId: 'squat',
      iniciada: DateTime(2026, 11, 4, 20, 0), // hora LOCAL
      finalizada: DateTime(2026, 11, 4, 20, 5),
      repsTotales: 3,
      repsCorrectas: 2,
      repsIncorrectas: 1,
      duracionSegundos: 300,
      eventos: const [
        {'numero_rep': 1, 'es_correcta': true, 'errores': <String>[]},
        {
          'numero_rep': 2,
          'es_correcta': false,
          'errores': ['profundidad_insuficiente'],
        },
      ],
      intentos: intentos,
    );

void main() {
  late ColaSesiones cola;
  setUp(() => cola = ColaSesiones(AlmacenMemoria()));

  group('UUID', () {
    test('formato v4 válido y distinto cada vez', () {
      final patron = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final a = generarUuidV4(), b = generarUuidV4();
      expect(a, matches(patron));
      expect(a, isNot(b));
    });
  });

  group('Fechas', () {
    test('se envían en UTC (con "Z"), no como hora local sin zona', () {
      final p = sesion('a').paramsSesion();
      expect(p['iniciada_en'], endsWith('Z'));
      final enviada = DateTime.parse(p['iniciada_en'] as String);
      expect(enviada.isAtSameMomentAs(DateTime(2026, 11, 4, 20, 0)), isTrue);
    });
  });

  group('Cola', () {
    test('guardar y leer conserva todos los datos', () async {
      await cola.agregar(sesion('a'));
      final leida = (await cola.pendientes()).single;
      expect(leida.id, 'a');
      expect(leida.repsCorrectas, 2);
      expect(leida.eventos[1]['errores'], ['profundidad_insuficiente']);
      expect(leida.iniciada.isAtSameMomentAs(DateTime(2026, 11, 4, 20, 0)),
          isTrue);
      expect(leida.aEventos()[1].esCorrecta, isFalse);
      expect(leida.aResumen().pendiente, isTrue);
    });

    test('agregar el mismo id lo reemplaza (no duplica)', () async {
      await cola.agregar(sesion('a'));
      await cola.agregar(sesion('a', intentos: 2));
      final lista = await cola.pendientes();
      expect(lista, hasLength(1));
      expect(lista.single.intentos, 2);
    });

    test('solo devuelve las del usuario pedido', () async {
      await cola.agregar(sesion('a', usuario: 'u1'));
      await cola.agregar(sesion('b', usuario: 'u2'));
      expect((await cola.pendientes(userId: 'u1')).map((s) => s.id), ['a']);
    });
  });

  group('Sincronizar', () {
    test('con conexión: sube todas y vacía la cola', () async {
      await cola.agregar(sesion('a'));
      await cola.agregar(sesion('b'));
      final subidas = <String>[];
      final n = await cola.sincronizar(
        userId: 'u1',
        subir: (s) async => subidas.add(s.id),
      );
      expect(n, 2);
      expect(subidas, ['a', 'b']);
      expect(await cola.pendientes(), isEmpty);
    });

    test('sin conexión: se detiene, no pierde nada y anota el intento',
        () async {
      await cola.agregar(sesion('a'));
      await cola.agregar(sesion('b'));
      var llamadas = 0;
      final n = await cola.sincronizar(
        userId: 'u1',
        subir: (s) async {
          llamadas++;
          throw Exception('sin red');
        },
      );
      expect(n, 0);
      expect(llamadas, 1); // no insiste con el resto
      final lista = await cola.pendientes();
      expect(lista, hasLength(2));
      expect(lista.firstWhere((s) => s.id == 'a').intentos, 1); // la 1ª falló
      expect(lista.firstWhere((s) => s.id == 'b').intentos, 0); // ni se probó
    });

    test('una sesión que siempre falla no bloquea a las demás', () async {
      await cola.agregar(sesion('mala', intentos: 3));
      await cola.agregar(sesion('buena'));
      final n = await cola.sincronizar(
        userId: 'u1',
        subir: (s) async {
          if (s.id == 'mala') throw Exception('error permanente');
        },
      );
      expect(n, 1);
      expect((await cola.pendientes()).single.id, 'mala');
    });

    test('nunca sube sesiones de otro usuario', () async {
      await cola.agregar(sesion('ajena', usuario: 'u2'));
      final subidas = <String>[];
      await cola.sincronizar(
          userId: 'u1', subir: (s) async => subidas.add(s.id));
      expect(subidas, isEmpty);
      expect(await cola.pendientes(userId: 'u2'), hasLength(1));
    });
  });
}