import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

//import '../ejercicios/sentadilla.dart';
//import 'pantalla_camara.dart';
//import 'pantalla_login.dart';
import 'pantalla_menu.dart';
//import 'pantalla_login.dart';
import 'pantalla_onboarding.dart';

/// Escucha el estado de autenticación y decide:
/// - con sesión  -> entra a la app
/// - sin sesión  -> muestra el login
class PortalAuth extends StatelessWidget {
  final List<CameraDescription> camaras;

  const PortalAuth({super.key, required this.camaras});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final sesion = Supabase.instance.client.auth.currentSession;
        if (sesion != null) {
          // Por ahora, logueado va directo a la sentadilla.
          // En el próximo sub-paso aquí irá el MENÚ de ejercicios.
          //return PantallaCamara(camaras: camaras, receta: recetaSentadilla); -> antiguo
          return PantallaMenu(camaras: camaras);
        }
        //return const PantallaLogin();
        return const PuertaEntrada();
      },
    );
  }
}