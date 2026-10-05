import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

//import 'pantallas/pantalla_camara.dart';
//recetas
//import 'ejercicios/sentadilla.dart';
//import 'ejercicios/curl_biceps.dart';
//import 'ejercicios/plancha.dart';

//RECOMENDACIONES PARA DESPLIGUE DESDE TERMINAL Y GENERAR APK
//Si alguna vez corres desde la terminal, tienes que pasar el archivo tú mismo:   flutter run --dart-define-from-file=env.json
//al generar el APK, también: flutter build apk --dart-define-from-file=env.json

import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'pantallas/portal_auth.dart';

Future<void> main() async {
  // Requerido para usar plugins (como la cámara) antes de arrancar la app.
  WidgetsFlutterBinding.ensureInitialized();
  //supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

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
      // Para probar, cambia la receta del home a -> home: PantallaCamara(camaras: camaras, receta: recetaPlancha),
      //home: PantallaCamara(camaras: camaras, receta: recetaCurl),
      home: PortalAuth(camaras: camaras),

    );
  }
}
