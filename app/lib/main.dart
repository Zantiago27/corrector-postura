import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'pantallas/pantalla_camara.dart';

Future<void> main() async {
  // Requerido para usar plugins (como la cámara) antes de arrancar la app.
  WidgetsFlutterBinding.ensureInitialized();
  // Obtenemos la lista de cámaras del dispositivo una sola vez.
  final camaras = await availableCameras();

  runApp(MiApp(camaras: camaras));
}

class MiApp extends StatelessWidget {
  final List<CameraDescription> camaras;

  const MiApp({super.key, required this.camaras});
  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Corrector de Postura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: PantallaCamara(camaras: camaras),
    );
  }
}
