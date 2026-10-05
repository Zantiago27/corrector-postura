import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ejercicios/receta_ejercicio.dart';
import '../ejercicios/sentadilla.dart';
import '../ejercicios/curl_biceps.dart';
import '../ejercicios/plancha.dart';
import 'pantalla_camara.dart';

/// Menú principal (pantalla de inicio tras el login):
/// el usuario elige qué ejercicio entrenar.
class PantallaMenu extends StatelessWidget {
  final List<CameraDescription> camaras;

  const PantallaMenu({super.key, required this.camaras});

  // Ejercicios disponibles. Agregar uno nuevo = una línea aquí.
  List<RecetaEjercicio> get _ejercicios =>
      [recetaSentadilla, recetaCurl, recetaPlancha];

  IconData _iconoPara(String id) {
    switch (id) {
      case 'squat':
        return Icons.airline_seat_legroom_reduced;
      case 'curl':
        return Icons.fitness_center;
      case 'plank':
        return Icons.align_horizontal_center;
      default:
        return Icons.sports_gymnastics;
    }
  }

  void _abrirEjercicio(BuildContext context, RecetaEjercicio receta) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PantallaCamara(camaras: camaras, receta: receta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final correo = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige un ejercicio'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (correo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hola, $correo',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _ejercicios.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = _ejercicios[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    leading:
                        Icon(_iconoPara(e.id), size: 36, color: Colors.teal),
                    title: Text(e.nombre,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    subtitle: Text(e.tipo == TipoEjercicio.isometrico
                        ? 'Isométrico · mide tiempo'
                        : 'Dinámico · cuenta repeticiones'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _abrirEjercicio(context, e),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}