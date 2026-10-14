import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/tema.dart';
import '../core/motor_ejercicio.dart';
import '../ejercicios/receta_ejercicio.dart';
import '../ejercicios/instrucciones_ejercicio.dart';
import '../ml/detector_pose.dart';
import '../servicios/servicio_voz.dart';
import '../servicios/servicio_comandos.dart';
import '../servicios/servicio_sesiones.dart';
import 'pintor_esqueleto.dart';
import 'pantalla_resumen.dart';

/// Fase visual de la pantalla: primero el usuario se acomoda ("prepárate"),
/// y al pulsar Empezar comienza el conteo ("entrenando").
enum _FaseVista { preparando, entrenando }

class PantallaCamara extends StatefulWidget {
  final List<CameraDescription> camaras;
  final RecetaEjercicio receta;

  const PantallaCamara({
    super.key,
    required this.camaras,
    required this.receta,
  });

  @override
  State<PantallaCamara> createState() => _PantallaCamaraState();
}

class _PantallaCamaraState extends State<PantallaCamara> {
  CameraController? _controlador;
  CameraDescription? _camaraActiva;
  final DetectorPose _detectorPose = DetectorPose();

  bool _permisoConcedido = false;
  bool _inicializando = true;
  bool _cambiandoCamara = false;
  String? _error;

  bool _procesando = false;
  ResultadoPose? _resultado;

  late final MotorEjercicio _motor;
  final ServicioVoz _voz = ServicioVoz();
  bool _vozActiva = true;

  // Comandos de voz (STT)
  final ServicioComandos _comandos = ServicioComandos();
  bool _comandosActivos = false;
  bool _sttDisponible = false;

  // Estado de la sesión en curso
  int _repeticiones = 0;
  double _anguloActual = 0;
  FaseMovimiento _fase = FaseMovimiento.arriba;
  List<ReglaForma> _errores = [];
  double _segundos = 0;
  bool _formaCorrecta = true;

  // Fase visual / encuadre
  _FaseVista _faseVista = _FaseVista.preparando;
  bool _encuadreOk = false;
  bool _mostrarTips = false; // reabrir tips durante el entrenamiento

  // Guardado
  final ServicioSesiones _servicioSesiones = ServicioSesiones();
  final List<RepeticionCompletada> _repsCompletadas = [];
  late DateTime _inicio;
  bool _guardando = false;

  bool get _esIsometrico => widget.receta.tipo == TipoEjercicio.isometrico;

  // Articulaciones que deben verse para considerar el cuerpo "encuadrado".
  static const _requeridos = [
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ];

  @override
  void initState() {
    super.initState();
    _motor = MotorEjercicio(widget.receta);
    _inicio = DateTime.now();
    _iniciarCamara();
    _voz.inicializar();
    // Mientras el entrenador habla, pausamos la escucha para no oírnos a
    // nosotros mismos; al terminar, reanudamos.
    _voz.alEmpezarHablar = () => _comandos.pausar();
    _voz.alTerminarHablar = () {
      if (_comandosActivos) _comandos.reanudar();
    };
    _initComandos();
  }

  Future<void> _initComandos() async {
    _sttDisponible = await _comandos.inicializar();
    if (mounted) setState(() {});
  }

  /// Activa/desactiva los comandos de voz.
  Future<void> _toggleComandos() async {
    if (!_sttDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El reconocimiento de voz no está disponible')));
      return;
    }
    if (_comandosActivos) {
      await _comandos.detener();
      setState(() => _comandosActivos = false);
    } else {
      setState(() => _comandosActivos = true);
      await _escucharFaseActual();
      if (_vozActiva) _voz.decir('Comandos de voz activados');
    }
  }

  /// Ajusta las palabras clave que se escuchan según la fase actual.
  Future<void> _escucharFaseActual() async {
    if (!_comandosActivos) return;
    if (_faseVista == _FaseVista.preparando) {
      await _comandos.escuchar(
        comandos: const [
          'empezar', 'empezamos', 'inicio', 'iniciar', 'vamos', 'comenzar'
        ],
        alDetectar: (_) {
          if (_encuadreOk && _faseVista == _FaseVista.preparando) _empezar();
        },
      );
    } else {
      await _comandos.escuchar(
        comandos: const [
          'fin', 'finalizar', 'finalizo', 'terminar', 'termina', 'terminamos'
        ],
        alDetectar: (_) {
          if (!_guardando) _finalizar();
        },
      );
    }
  }

  // --- Cámara ---

  Future<void> _iniciarCamara() async {
    final estado = await Permission.camera.request();
    if (!estado.isGranted) {
      setState(() {
        _permisoConcedido = false;
        _inicializando = false;
      });
      return;
    }
    _permisoConcedido = true;

    final camaraFrontal = widget.camaras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.camaras.first,
    );
    await _crearControlador(camaraFrontal);
  }

  /// Crea (o recrea) el controlador para una cámara concreta y arranca el
  /// stream. Se reutiliza al cambiar de cámara.
  Future<void> _crearControlador(CameraDescription camara) async {
    _camaraActiva = camara;
    final controlador = CameraController(
      camara,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await controlador.initialize();
      if (!mounted) return;
      await controlador.startImageStream(_procesarFrame);
      setState(() {
        _controlador = controlador;
        _inicializando = false;
        _cambiandoCamara = false;
        _procesando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo iniciar la cámara: $e';
        _inicializando = false;
        _cambiandoCamara = false;
      });
    }
  }

  /// Alterna entre cámara frontal y trasera (si el equipo tiene ambas).
  Future<void> _cambiarCamara() async {
    if (_controlador == null || _cambiandoCamara) return;
    final deseada = _camaraActiva?.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final nueva = widget.camaras.where((c) => c.lensDirection == deseada);
    if (nueva.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu dispositivo no tiene otra cámara')),
      );
      return;
    }
    setState(() => _cambiandoCamara = true);
    _procesando = true; // frena el procesamiento mientras cambiamos
    try {
      await _controlador?.stopImageStream();
    } catch (_) {}
    await _controlador?.dispose();
    _controlador = null;
    await _crearControlador(nueva.first);
  }

  // --- Procesamiento de frames ---

  Future<void> _procesarFrame(CameraImage imagen) async {
    if (_procesando) return;
    _procesando = true;
    try {
      final resultado = await _detectorPose.procesarFrame(
        imagen: imagen,
        controlador: _controlador!,
        camara: _camaraActiva!,
      );

      if (_faseVista == _FaseVista.preparando) {
        // Solo verificamos encuadre; el motor NO cuenta todavía.
        final ok = resultado.poses.isNotEmpty &&
            _cuerpoEncuadrado(resultado.poses.first);
        if (ok && !_encuadreOk && _vozActiva) {
          _voz.decir('Listo, ya estás en cuadro. Puedes empezar.');
        }
        _encuadreOk = ok;
        _errores = [];
      } else {
        // Entrenando: lógica del motor (conteo + reglas + voz).
        if (resultado.poses.isNotEmpty) {
          final evaluacion = _motor.evaluar(resultado.poses.first);
          if (evaluacion != null) {
            if (evaluacion.repCompletada != null) {
              _repsCompletadas.add(evaluacion.repCompletada!);
            }
            final repsAntes = _repeticiones;
            _repeticiones = evaluacion.repeticiones;
            _anguloActual = evaluacion.anguloPrincipal;
            _fase = evaluacion.fase;
            _errores = evaluacion.erroresActivos;
            _segundos = evaluacion.segundosMantenidos;
            _formaCorrecta = evaluacion.formaCorrecta;

            if (_vozActiva) {
              if (_errores.isNotEmpty) {
                final graves =
                    _errores.where((e) => e.severidad == Severidad.alta);
                _voz.decir(
                  (graves.isNotEmpty ? graves.first : _errores.first).mensaje,
                );
              } else if (_repeticiones > repsAntes) {
                _voz.decirNumero(_repeticiones);
              }
            }
          } else {
            _errores = [];
            _motor.pausar();
          }
        } else {
          _errores = [];
        }
      }

      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      debugPrint('Error procesando frame: $e');
    } finally {
      _procesando = false;
    }
  }

  /// ¿Se ven las articulaciones clave con suficiente confianza?
  bool _cuerpoEncuadrado(Pose pose) {
    for (final t in _requeridos) {
      final lm = pose.landmarks[t];
      if (lm == null || lm.likelihood < 0.5) return false;
    }
    return true;
  }

  // --- Acciones ---

  void _empezar() {
    if (!_encuadreOk) return;
    _motor.reiniciar();
    _voz.reiniciar();
    _repsCompletadas.clear();
    _repeticiones = 0;
    _segundos = 0;
    _inicio = DateTime.now();
    setState(() {
      _faseVista = _FaseVista.entrenando;
      _mostrarTips = false;
    });
    if (_vozActiva) _voz.decir('Comencemos');
    // Cambia las palabras clave: ahora escuchamos "finalizar".
    _escucharFaseActual();
  }

  void _reiniciar() {
    _motor.reiniciar();
    _voz.reiniciar();
    _segundos = 0;
    _repsCompletadas.clear();
    _inicio = DateTime.now();
    setState(() => _repeticiones = 0);
  }

  void _toggleVoz() {
    setState(() => _vozActiva = !_vozActiva);
    if (!_vozActiva) _voz.reiniciar(); // corta lo que esté diciendo
  }

  Future<void> _finalizar() async {
    setState(() => _guardando = true);
    _procesando = true;
    try {
      await _controlador?.stopImageStream();
    } catch (_) {}

    try {
      await _servicioSesiones.guardarSesion(
        ejercicioId: widget.receta.id,
        iniciada: _inicio,
        repsTotales: _repeticiones,
        repsCorrectas: _motor.repsCorrectas,
        repsIncorrectas: _motor.repsIncorrectas,
        duracionSegundos: _esIsometrico
            ? _segundos.round()
            : DateTime.now().difference(_inicio).inSeconds,
        repeticiones: _repsCompletadas,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaResumen(
            camaras: widget.camaras,
            receta: widget.receta,
            repsTotales: _repeticiones,
            repsCorrectas: _motor.repsCorrectas,
            repsIncorrectas: _motor.repsIncorrectas,
            duracionSegundos: _esIsometrico
                ? _segundos.round()
                : DateTime.now().difference(_inicio).inSeconds,
            repeticiones: _repsCompletadas,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')));
      _procesando = false;
      setState(() => _guardando = false);
      try {
        await _controlador?.startImageStream(_procesarFrame);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _detectorPose.cerrar();
    _voz.cerrar();
    _comandos.cerrar();
    _controlador?.dispose();
    super.dispose();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.oscuro,
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (_inicializando) {
      return const Center(child: CircularProgressIndicator(color: Colores.acento));
    }
    if (!_permisoConcedido) return _vistaPermiso();
    if (_error != null) return _vistaError();

    return Stack(
      children: [
        _preview(),
        _barraSuperior(),
        if (_faseVista == _FaseVista.entrenando) _hudContador(),
        _panelInferior(),
        if (_cambiandoCamara)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(
                  child: CircularProgressIndicator(color: Colores.acento)),
            ),
          ),
      ],
    );
  }

  Widget _preview() {
    return Positioned.fill(
      child: Center(
        child: CameraPreview(
          _controlador!,
          child: _resultado == null
              ? const SizedBox.shrink()
              : CustomPaint(
                  painter: PintorEsqueleto(
                    poses: _resultado!.poses,
                    tamanoImagen: _resultado!.tamanoImagen,
                    rotacion: _resultado!.rotacion,
                    lente: _camaraActiva!.lensDirection,
                    formaCorrecta: _errores.isEmpty && _formaCorrecta,
                  ),
                ),
        ),
      ),
    );
  }

  // Barra superior: volver · nombre · (reiniciar) · cambiar cámara · voz
  Widget _barraSuperior() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _botonCircular(Icons.close_rounded, () => Navigator.of(context).pop()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.receta.nombre,
                    style: Tipografia.sora(14,
                        peso: FontWeight.w700, color: Colors.white)),
              ),
              const Spacer(),
              if (_faseVista == _FaseVista.entrenando)
                _botonCircular(Icons.refresh_rounded, _reiniciar),
              if (_sttDisponible)
                _botonCircular(
                  _comandosActivos ? Icons.mic_rounded : Icons.mic_none_rounded,
                  _toggleComandos,
                  activo: _comandosActivos,
                ),
              _botonCircular(Icons.cameraswitch_rounded, _cambiarCamara),
              _botonCircular(
                _vozActiva ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                _toggleVoz,
                activo: _vozActiva,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonCircular(IconData icono, VoidCallback onTap, {bool activo = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: activo
                ? Colores.acento
                : Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // Contador grande (solo entrenando)
  Widget _hudContador() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 66),
          child: Column(
            children: [
              Text(_esIsometrico ? 'TIEMPO' : 'REPETICIONES',
                  style: Tipografia.manrope(12,
                      peso: FontWeight.w800,
                      color: Colors.white.withOpacity(0.55))),
              SizedBox(
                height: 92,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _esIsometrico
                        ? '${_segundos.toStringAsFixed(0)}s'
                        : '$_repeticiones',
                    style: Tipografia.sora(88,
                        peso: FontWeight.w800, color: Colors.white, altura: 1),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pill('${_motor.repsCorrectas} correctas', Colores.ok),
                  const SizedBox(width: 10),
                  _pill('${_motor.repsIncorrectas} a corregir', Colores.acento),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String texto, Color punto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: punto, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(texto,
              style: Tipografia.manrope(13,
                  peso: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  // Panel inferior: cambia según la fase.
  Widget _panelInferior() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _faseVista == _FaseVista.preparando
              ? _controlesPreparando()
              : _controlesEntrenando(),
        ),
      ),
    );
  }

  // --- Fase Prepárate ---
  Widget _controlesPreparando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bannerEncuadre(),
        const SizedBox(height: 12),
        _tarjetaTips(),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _encuadreOk ? _empezar : null,
          style: FilledButton.styleFrom(
            backgroundColor: _encuadreOk ? Colores.acento : const Color(0xFF3A352F),
            foregroundColor:
                _encuadreOk ? Colores.sobreAcento : Colors.white54,
            minimumSize: const Size.fromHeight(Medidas.alturaBoton),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Medidas.radioBoton)),
          ),
          child: Text(_encuadreOk ? 'Empezar' : 'Acomódate para empezar'),
        ),
      ],
    );
  }

  Widget _bannerEncuadre() {
    final ok = _encuadreOk;
    final color = ok ? Colores.ok : Colores.acento;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.center_focus_weak_rounded,
              color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? 'Perfecto, se te ve completo'
                  : 'Acomódate: que se vea todo tu cuerpo',
              style: Tipografia.manrope(14,
                  peso: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaTips() {
    final tips = instruccionesDe(widget.receta.id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cómo colocarte',
              style: Tipografia.manrope(12,
                  peso: FontWeight.w800,
                  color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 10),
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 10),
                      child: Icon(Icons.radio_button_checked,
                          color: Colores.acento, size: 14),
                    ),
                    Expanded(
                      child: Text(t,
                          style: Tipografia.manrope(13.5,
                              color: Colors.white, altura: 1.35)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // --- Fase Entrenando ---
  Widget _controlesEntrenando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_mostrarTips) ...[
          _tarjetaTips(),
          const SizedBox(height: 10),
        ],
        _bannerFeedback(),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _mostrarTips = !_mostrarTips),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: Text(_mostrarTips ? 'Ocultar' : '¿Cómo me coloco?',
                  style: Tipografia.manrope(13, peso: FontWeight.w700)),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: _guardando ? null : _finalizar,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colores.oscuro,
            minimumSize: const Size.fromHeight(Medidas.alturaBoton),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Medidas.radioBoton)),
          ),
          child: _guardando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colores.oscuro))
              : const Text('Terminar entrenamiento'),
        ),
      ],
    );
  }

  Widget _bannerFeedback() {
    final hayError = _errores.isNotEmpty || !_formaCorrecta;
    final color = hayError ? Colores.acento : Colores.ok;
    final titulo = hayError ? 'CORRIGE' : 'BUENA FORMA';
    final mensaje = _errores.isNotEmpty
        ? _errores.first.mensaje
        : (_formaCorrecta ? 'Sigue así, mantén el ritmo' : 'Ajusta tu postura');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                shape: BoxShape.circle),
            child: Icon(hayError ? Icons.priority_high_rounded : Icons.check_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: Tipografia.manrope(11,
                        peso: FontWeight.w800,
                        color: Colors.white.withOpacity(0.8))),
                Text(mensaje,
                    style: Tipografia.sora(15,
                        peso: FontWeight.w700, color: Colors.white, altura: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Estados de permiso / error ---
  Widget _vistaPermiso() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text('Necesitamos tu cámara',
                style: Tipografia.sora(20, color: Colors.white),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Actívala para analizar tu técnica. El video nunca sale del teléfono.',
                style: Tipografia.manrope(14, color: Colors.white70),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: openAppSettings,
                child: const Text('Abrir ajustes')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _inicializando = true);
                _iniciarCamara();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(_error ?? 'Ocurrió un error',
                style: Tipografia.manrope(15, color: Colors.white),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}