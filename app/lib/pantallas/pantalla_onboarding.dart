// lib/pantallas/pantalla_onboarding.dart
//
// Pantalla de bienvenida (primera vez que se abre la app) + la "puerta de
// entrada" que decide si mostrar el onboarding o ir directo al login.
//
// Flujo (sin sesión): primera vez -> Onboarding -> Login.
//                      siguientes  -> Login directo.
// Usa shared_preferences para recordar que ya se vio el onboarding.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/tema.dart';
import 'pantalla_login.dart';

/// Clave en preferencias para no volver a mostrar el onboarding.
const _kOnboardingVisto = 'onboarding_visto';

/// Decide qué mostrar cuando no hay sesión: onboarding (una vez) o login.
class PuertaEntrada extends StatefulWidget {
  const PuertaEntrada({super.key});

  @override
  State<PuertaEntrada> createState() => _PuertaEntradaState();
}

class _PuertaEntradaState extends State<PuertaEntrada> {
  bool? _mostrarOnboarding; // null = aún cargando

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final visto = prefs.getBool(_kOnboardingVisto) ?? false;
      if (!mounted) return;
      setState(() => _mostrarOnboarding = !visto);
    } catch (_) {
      // Si algo falla, no bloqueamos al usuario: vamos al login.
      if (!mounted) return;
      setState(() => _mostrarOnboarding = false);
    }
  }

  Future<void> _completarOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingVisto, true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _mostrarOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_mostrarOnboarding == null) {
      return const Scaffold(
        backgroundColor: Colores.fondoApp,
        body: Center(child: CircularProgressIndicator(color: Colores.acento)),
      );
    }
    if (_mostrarOnboarding!) {
      return PantallaOnboarding(onContinuar: _completarOnboarding);
    }
    return const PantallaLogin();
  }
}

/// Pantalla de bienvenida (estilo SmartForm).
class PantallaOnboarding extends StatelessWidget {
  /// Se llama al pulsar cualquiera de los dos botones de avance.
  final VoidCallback onContinuar;

  const PantallaOnboarding({super.key, required this.onContinuar});

  Future<void> _permitirCamara() async {
    // Pedimos el permiso aquí para que la primera experiencia en la cámara
    // sea fluida. Pase lo que pase, continuamos al login.
    try {
      await Permission.camera.request();
    } catch (_) {}
    onContinuar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo + nombre
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colores.acento,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colores.sobreAcento, width: 3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('SmartForm',
                            style: Tipografia.sora(22, peso: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    // Ilustración (silueta con puntos)
                    Container(
                      height: 210,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EDE6),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: const Color(0xFFD6CFC3),
                            style: BorderStyle.solid),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.accessibility_new_rounded,
                          size: 110, color: Colores.acento),
                    ),
                    const SizedBox(height: 28),
                    Text('Corrige tu técnica\nen tiempo real.',
                        style:
                            Theme.of(context).textTheme.displayLarge),
                    const SizedBox(height: 12),
                    Text(
                      'Tu cámara analiza cada repetición, cuenta tus series y '
                      'te avisa al instante si tu forma no es correcta. Todo '
                      'funciona dentro del teléfono.',
                      style: Tipografia.manrope(15,
                          color: Colores.suave, altura: 1.5),
                    ),
                  ],
                ),
              ),
              // Tarjeta de privacidad de cámara
              Container(
                padding: const EdgeInsets.all(16),
                decoration: Componentes.tarjeta(radio: 18),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colores.acentoSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.videocam_rounded,
                          color: Colores.acento, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Necesitamos tu cámara',
                              style: Tipografia.manrope(14,
                                  peso: FontWeight.w700)),
                          Text('El video nunca sale del dispositivo.',
                              style: Tipografia.manrope(12.5,
                                  color: Colores.suave)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _permitirCamara,
                child: const Text('Permitir cámara y empezar'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onContinuar,
                style: TextButton.styleFrom(foregroundColor: Colores.suave),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}