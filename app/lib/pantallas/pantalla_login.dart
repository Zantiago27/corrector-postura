import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/tema.dart';

/// Pantalla única de acceso: alterna entre iniciar sesión y crear cuenta
/// (estilo SmartForm, con pestañas). El PortalAuth reacciona al cambio de
/// sesión, así que aquí no navegamos a mano tras autenticar.
class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _esRegistro = false;
  bool _cargando = false;
  bool _verPassword = false;

  Future<void> _enviar() async {
    final nombre = _nombre.text.trim();
    final email = _email.text.trim();
    final pass = _password.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _mostrar('Completa el correo y la contraseña');
      return;
    }
    if (_esRegistro && pass.length < 6) {
      _mostrar('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    setState(() => _cargando = true);
    try {
      if (_esRegistro) {
        await _supabase.auth.signUp(
          email: email,
          password: pass,
          // Guardamos el nombre en los metadatos del usuario (opcional).
          data: nombre.isNotEmpty ? {'nombre': nombre} : null,
        );
      } else {
        await _supabase.auth
            .signInWithPassword(email: email, password: pass);
      }
    } on AuthException catch (e) {
      _mostrar(e.message);
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
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 40, 26, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colores.acento,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colores.sobreAcento, width: 3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(_esRegistro ? 'Crea tu cuenta' : 'Bienvenido de vuelta',
                  style: Theme.of(context).textTheme.displayMedium),
              const SizedBox(height: 6),
              Text(
                _esRegistro
                    ? 'Empieza a corregir tu técnica hoy.'
                    : 'Entra para seguir tu progreso.',
                style: Tipografia.manrope(14, color: Colores.suave),
              ),
              const SizedBox(height: 26),

              // Pestañas iniciar sesión / crear cuenta
              _pestanas(),
              const SizedBox(height: 22),

              // Campos
              if (_esRegistro) ...[
                _campo('Nombre', _nombre,
                    hint: 'Tu nombre', icono: Icons.person_outline_rounded),
                const SizedBox(height: 14),
              ],
              _campo('Correo', _email,
                  hint: 'tucorreo@ejemplo.com',
                  icono: Icons.mail_outline_rounded,
                  teclado: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _campoPassword(),
              const SizedBox(height: 26),

              // Botón principal
              FilledButton(
                onPressed: _cargando ? null : _enviar,
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colores.sobreAcento),
                      )
                    : Text(_esRegistro ? 'Crear cuenta' : 'Iniciar sesión'),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _cargando
                      ? null
                      : () => setState(() => _esRegistro = !_esRegistro),
                  style: TextButton.styleFrom(foregroundColor: Colores.suave),
                  child: Text.rich(TextSpan(
                    text: _esRegistro
                        ? '¿Ya tienes cuenta? '
                        : '¿No tienes cuenta? ',
                    style: Tipografia.manrope(14, color: Colores.suave),
                    children: [
                      TextSpan(
                        text: _esRegistro ? 'Inicia sesión' : 'Crear cuenta',
                        style: Tipografia.manrope(14,
                            peso: FontWeight.w800, color: Colores.acento),
                      ),
                    ],
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pestanas() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EDE6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('Iniciar sesión', !_esRegistro, () {
            if (_esRegistro) setState(() => _esRegistro = false);
          }),
          _tab('Crear cuenta', _esRegistro, () {
            if (!_esRegistro) setState(() => _esRegistro = true);
          }),
        ],
      ),
    );
  }

  Widget _tab(String texto, bool activo, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? Colores.tarjeta : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: activo
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Text(texto,
              style: Tipografia.manrope(14,
                  peso: FontWeight.w700,
                  color: activo ? Colores.tinta : Colores.suave)),
        ),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl,
      {String? hint, IconData? icono, TextInputType? teclado}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Tipografia.manrope(12.5,
                peso: FontWeight.w700, color: Colores.suave)),
        const SizedBox(height: 7),
        TextField(
          controller: ctrl,
          keyboardType: teclado,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icono != null
                ? Icon(icono, color: Colores.suave, size: 20)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _campoPassword() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contraseña',
            style: Tipografia.manrope(12.5,
                peso: FontWeight.w700, color: Colores.suave)),
        const SizedBox(height: 7),
        TextField(
          controller: _password,
          obscureText: !_verPassword,
          decoration: InputDecoration(
            hintText: '••••••',
            prefixIcon:
                const Icon(Icons.lock_outline_rounded, color: Colores.suave, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _verPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colores.suave,
                  size: 20),
              onPressed: () => setState(() => _verPassword = !_verPassword),
            ),
          ),
        ),
      ],
    );
  }
}