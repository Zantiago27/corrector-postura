// lib/pantallas/pantalla_ajustes.dart
//
// Ajustes (Fase G): perfil (nombre), voz del entrenador y privacidad.
// Los cambios de voz y privacidad se guardan solos al tocarlos; el nombre
// se guarda con su botón (va a Supabase).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/tema.dart';
import '../servicios/registro_rendimiento.dart';
import '../servicios/servicio_ajustes.dart';
import '../servicios/servicio_voz.dart';

class PantallaAjustes extends StatefulWidget {
  const PantallaAjustes({super.key});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  final _voz = ServicioVoz();
  final _nombre = TextEditingController();

  Ajustes _ajustes = const Ajustes();
  bool _cargando = true;
  bool _guardandoNombre = false;
  int _numRegistros = 0; // filas del registro de rendimiento (Fase I.1)

  @override
  void initState() {
    super.initState();
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final nombre = meta?['nombre'];
    if (nombre is String) _nombre.text = nombre;
    _cargar();
  }

  Future<void> _cargar() async {
    final a = await ServicioAjustes.cargar();
    await _voz.inicializar(
        tono: a.tono, velocidad: a.velocidad, idioma: a.idiomaVoz);
    final registros = await ServicioRegistroRendimiento.listar();
    if (!mounted) return;
    setState(() {
      _ajustes = a;
      _numRegistros = registros.length;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _voz.cerrar();
    _nombre.dispose();
    super.dispose();
  }

  /// Aplica y guarda un cambio de voz/privacidad.
  Future<void> _cambiar(Ajustes nuevo) async {
    setState(() => _ajustes = nuevo);
    await ServicioAjustes.guardar(nuevo);
    await _voz.configurar(
      tono: nuevo.tono,
      velocidad: nuevo.velocidad,
      idioma: nuevo.idiomaVoz,
    );
  }

  void _probarVoz() =>
      _voz.decirCoach('Baja más. Pecho arriba. ¡Eso es, tres!',
          interrumpir: true);

  Future<void> _guardarNombre() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _guardandoNombre = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {'nombre': nombre}));
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre actualizado')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo guardar. Revisa tu conexión.')),
      );
    } finally {
      if (mounted) setState(() => _guardandoNombre = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondoApp,
      appBar: AppBar(
        backgroundColor: Colores.fondoApp,
        title: Text('Ajustes', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colores.acento))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Medidas.paddingPantalla, 8, Medidas.paddingPantalla, 32),
              children: [
                _titulo('Perfil'),
                _seccionPerfil(),
                const SizedBox(height: 24),
                _titulo('Voz del entrenador'),
                _seccionVoz(),
                const SizedBox(height: 24),
                _titulo('Privacidad'),
                _seccionPrivacidad(),
                const SizedBox(height: 24),
                _titulo('Cámara'),
                _seccionCamara(),
                const SizedBox(height: 24),
                _titulo('Diagnóstico'),
                _seccionDiagnostico(),
              ],
            ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texto.toUpperCase(),
            style: Tipografia.manrope(12,
                peso: FontWeight.w800, color: Colores.suave)),
      );

  // --- Perfil ---
  Widget _seccionPerfil() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Componentes.tarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Cómo quieres que te llame?',
              style: Tipografia.manrope(14, peso: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'Tu nombre',
              counterText: '',
            ),
            onSubmitted: (_) => _guardarNombre(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _guardandoNombre ? null : _guardarNombre,
            child: _guardandoNombre
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colores.sobreAcento),
                  )
                : const Text('Guardar nombre'),
          ),
        ],
      ),
    );
  }

  // --- Voz ---
  Widget _seccionVoz() {
    final a = _ajustes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: Componentes.tarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Colores.acento,
            title: Text('Voz activada al empezar',
                style: Tipografia.manrope(14, peso: FontWeight.w700)),
            subtitle: Text('Puedes silenciarla durante el entrenamiento',
                style: Tipografia.manrope(12.5, color: Colores.suave)),
            value: a.vozActiva,
            onChanged: (v) => _cambiar(a.copyWith(vozActiva: v)),
          ),
          const SizedBox(height: 8),
          Text('Acento', style: Tipografia.manrope(14, peso: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AcentoVoz>(
              segments: const [
                ButtonSegment(
                    value: AcentoVoz.latino, label: Text('Latinoamérica')),
                ButtonSegment(value: AcentoVoz.espana, label: Text('España')),
              ],
              selected: {a.acento},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _cambiar(a.copyWith(acento: s.first)),
            ),
          ),
          const SizedBox(height: 16),
          _deslizador(
            titulo: 'Velocidad',
            valor: a.velocidad,
            min: 0.3,
            max: 0.7,
            etiqueta: a.velocidad < 0.43
                ? 'Lenta'
                : (a.velocidad > 0.57 ? 'Rápida' : 'Normal'),
            alCambiar: (v) => setState(() => _ajustes = a.copyWith(velocidad: v)),
            alSoltar: (v) => _cambiar(_ajustes.copyWith(velocidad: v)),
          ),
          _deslizador(
            titulo: 'Tono',
            valor: a.tono,
            min: 0.7,
            max: 1.3,
            etiqueta:
                a.tono < 0.9 ? 'Grave' : (a.tono > 1.1 ? 'Agudo' : 'Natural'),
            alCambiar: (v) => setState(() => _ajustes = a.copyWith(tono: v)),
            alSoltar: (v) => _cambiar(_ajustes.copyWith(tono: v)),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _probarVoz,
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('Probar voz'),
          ),
        ],
      ),
    );
  }

  Widget _deslizador({
    required String titulo,
    required double valor,
    required double min,
    required double max,
    required String etiqueta,
    required ValueChanged<double> alCambiar,
    required ValueChanged<double> alSoltar,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: Tipografia.manrope(14, peso: FontWeight.w700)),
            Text(etiqueta,
                style: Tipografia.manrope(13,
                    peso: FontWeight.w700, color: Colores.acentoTexto)),
          ],
        ),
        Slider(
          value: valor.clamp(min, max),
          min: min,
          max: max,
          activeColor: Colores.acento,
          onChanged: alCambiar,
          onChangeEnd: alSoltar,
        ),
      ],
    );
  }

  // --- Privacidad ---
  Widget _seccionPrivacidad() {
    final a = _ajustes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: Componentes.tarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Colores.acento,
            title: Text('Comandos de voz solo en el teléfono',
                style: Tipografia.manrope(14, peso: FontWeight.w700)),
            subtitle: Text(
              a.reconocimientoSoloDispositivo
                  ? 'Tu voz se reconoce en el teléfono y no se envía a '
                      'internet. Si tu teléfono no lo permite, los comandos '
                      'de voz no estarán disponibles.'
                  : 'El reconocimiento puede usar el servicio de Google, '
                      'que envía el audio de los comandos a sus servidores.',
              style: Tipografia.manrope(12.5, color: Colores.suave),
            ),
            value: a.reconocimientoSoloDispositivo,
            onChanged: (v) =>
                _cambiar(a.copyWith(reconocimientoSoloDispositivo: v)),
          ),
          const Divider(color: Colores.linea),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  color: Colores.ok, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El video de la cámara nunca sale de tu teléfono. Solo se '
                  'guardan tus resultados (repeticiones, errores y tiempos).',
                  style: Tipografia.manrope(12.5,
                      color: Colores.suave, altura: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

    // --- Cámara (Fase I.6) ---
  Widget _seccionCamara() {
    final a = _ajustes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: Componentes.tarjeta(),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: Colores.acento,
        title: Text('Modo rendimiento',
            style: Tipografia.manrope(14, peso: FontWeight.w700)),
        subtitle: Text(
          'Usa menos resolución de cámara para que el análisis vaya fluido '
          'en teléfonos lentos. Se activa solo si tu teléfono lo necesita.',
          style: Tipografia.manrope(12.5, color: Colores.suave),
        ),
        value: a.calidadReducida,
        onChanged: (v) => _cambiar(a.copyWith(calidadReducida: v)),
      ),
    );
  }

  // --- Diagnóstico (Fase I.1) ---
  Widget _seccionDiagnostico() {
    final a = _ajustes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: Componentes.tarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Colores.acento,
            title: Text('Modo diagnóstico',
                style: Tipografia.manrope(14, peso: FontWeight.w700)),
            subtitle: Text(
              'Muestra FPS y tiempos de análisis al entrenar y guarda un '
              'resumen de cada sesión en este teléfono. Para pruebas.',
              style: Tipografia.manrope(12.5, color: Colores.suave),
            ),
            value: a.modoDiagnostico,
            onChanged: (v) => _cambiar(a.copyWith(modoDiagnostico: v)),
          ),
          const Divider(color: Colores.linea),
          const SizedBox(height: 6),
          Text(
            _numRegistros == 1
                ? '1 sesión registrada'
                : '$_numRegistros sesiones registradas',
            style: Tipografia.manrope(14, peso: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _numRegistros == 0 ? null : _copiarRegistro,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copiar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _numRegistros == 0 ? null : _borrarRegistro,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Borrar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Copia el registro como tabla (tabuladores) para pegarlo en la planilla.
  Future<void> _copiarRegistro() async {
    final registros = await ServicioRegistroRendimiento.listar();
    if (registros.isEmpty) return;
    await Clipboard.setData(
        ClipboardData(text: RegistroRendimiento.comoTabla(registros)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${registros.length} sesiones copiadas. '
          'Pégalas en la planilla.'),
    ));
  }

  Future<void> _borrarRegistro() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar el registro?'),
        content: const Text('Se eliminarán los datos de rendimiento '
            'guardados en este teléfono. Cópialos antes si los necesitas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmar != true) return;
    await ServicioRegistroRendimiento.borrar();
    if (!mounted) return;
    setState(() => _numRegistros = 0);
  }


}