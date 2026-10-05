import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla única que sirve para iniciar sesión y para registrarse.
class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _esRegistro = false; // false = iniciar sesión, true = registrarse
  bool _cargando = false;

  Future<void> _enviar() async {
    final email = _email.text.trim();
    final pass = _password.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _mostrar('Completa el correo y la contraseña');
      return;
    }
    setState(() => _cargando = true);
    try {
      if (_esRegistro) {
        await _supabase.auth.signUp(email: email, password: pass);
      } else {
        await _supabase.auth.signInWithPassword(email: email, password: pass);
      }
      // No navegamos a mano: el PortalAuth reacciona solo al cambio de sesión.
    } on AuthException catch (e) {
      _mostrar(e.message); // ej. credenciales inválidas
    } catch (e) {
      _mostrar('Ocurrió un error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center, size: 64, color: Colors.teal),
              const SizedBox(height: 8),
              Text(
                _esRegistro ? 'Crear cuenta' : 'Iniciar sesión',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _cargando ? null : _enviar,
                  child: _cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_esRegistro ? 'Registrarme' : 'Entrar'),
                ),
              ),
              TextButton(
                onPressed: _cargando
                    ? null
                    : () => setState(() => _esRegistro = !_esRegistro),
                child: Text(_esRegistro
                    ? '¿Ya tienes cuenta? Inicia sesión'
                    : '¿No tienes cuenta? Regístrate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}