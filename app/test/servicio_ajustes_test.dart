import 'package:corrector_postura/servicios/servicio_ajustes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('valores por defecto: voz natural y micrófono privado', () async {
    final a = await ServicioAjustes.cargar();
    expect(a.tono, 1.0);
    expect(a.velocidad, 0.5);
    expect(a.vozActiva, isTrue);
    expect(a.reconocimientoSoloDispositivo, isTrue); // privado por defecto
    expect(a.idiomaVoz, 'es-MX');
  });

  test('guardar y volver a cargar conserva los cambios', () async {
    await ServicioAjustes.guardar(const Ajustes().copyWith(
      tono: 1.2,
      velocidad: 0.4,
      acento: AcentoVoz.espana,
      vozActiva: false,
      reconocimientoSoloDispositivo: false,
    ));
    final a = await ServicioAjustes.cargar();
    expect(a.tono, 1.2);
    expect(a.velocidad, 0.4);
    expect(a.acento, AcentoVoz.espana);
    expect(a.idiomaVoz, 'es-ES');
    expect(a.idiomaReconocimiento, 'es_ES');
    expect(a.vozActiva, isFalse);
    expect(a.reconocimientoSoloDispositivo, isFalse);
  });
}