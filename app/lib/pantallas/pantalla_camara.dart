import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/tema.dart';
import '../core/coach_entrenamiento.dart';
import '../core/controlador_entrenamiento.dart';
import '../ejercicios/instrucciones_ejercicio.dart';
import '../ejercicios/receta_ejercicio.dart';
import '../ml/detector_pose.dart';
import '../servicios/servicio_comandos.dart';
import '../servicios/servicio_ajustes.dart';
import '../servicios/servicio_sesiones.dart';
import '../servicios/servicio_voz.dart';
import 'figura_animada.dart';
import 'pantalla_resumen.dart';
import 'pintor_esqueleto.dart';
import 'widgets_coaching.dart';

/// Pantalla de entrenamiento.
///
/// Se encarga de lo "físico": cámara, permisos, voz y dibujo. La lógica del
/// entrenamiento (estados, conteo, coaching, datos de la serie) vive en
/// ControladorEntrenamiento.
///
/// Fase D: flujo manos libres (inicio automático con cuenta regresiva y
/// pausa automática), silueta guía y soporte de orientación horizontal.
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

class _PantallaCamaraState extends State<PantallaCamara>
    with WidgetsBindingObserver {
  // --- Cámara ---
  CameraController? _controlador;
  CameraDescription? _camaraActiva;
  final DetectorPose _detectorPose = DetectorPose();

  bool _permisoConcedido = false;
  bool _inicializando = true;
  bool _cambiandoCamara = false;
  String? _error;

  // Cada controlador nuevo recibe un número de "generación".
  // Los frames que lleguen con un número viejo se descartan: así un frame
  // de la cámara anterior nunca toca el estado ni la UI.
  int _generacionCamara = 0;

  // true si liberamos la cámara porque la app pasó a segundo plano.
  bool _camaraLiberada = false;

  bool _procesando = false;
  ResultadoPose? _resultado;

  // --- Entrenamiento ---
  late final ControladorEntrenamiento _entreno;

  // --- Voz (TTS) ---
  final ServicioVoz _voz = ServicioVoz();
  bool _vozActiva = true;

  // --- Comandos de voz (STT) ---
  final ServicioComandos _comandos = ServicioComandos();
  bool _comandosActivos = false;
  bool _sttDisponible = false;

  // --- UI / guardado ---
  bool _mostrarTips = false;
  final ServicioSesiones _servicioSesiones = ServicioSesiones();
  bool _guardando = false;

  bool get _entrenando => _entreno.entrenando;
  bool get _esIsometrico => _entreno.esIsometrico;
  GuiaEjercicio get _guia => guiaDe(widget.receta.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // la pantalla no se apaga mientras entrenas
    // En esta pantalla se permite girar el teléfono (ejercicios de suelo).
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    _entreno = ControladorEntrenamiento(widget.receta);
    _iniciarCamara();
    _cargarAjustes();
    _comandos.alFallarEnDispositivo = _alFallarComandosEnDispositivo;
    // Mientras el entrenador habla, pausamos la escucha para no oírnos a
    // nosotros mismos; al terminar, reanudamos.
    _voz.alEmpezarHablar = () => _comandos.pausar();
    _voz.alTerminarHablar = () {
      if (_comandosActivos) _comandos.reanudar();
    };
    _initComandos();
  }

  // ===========================================================================
  // COMANDOS DE VOZ
  // ===========================================================================

  Future<void> _initComandos() async {
    _sttDisponible = await _comandos.inicializar();
    if (mounted) setState(() {});
  }

  /// Aplica las preferencias guardadas (voz y privacidad del micrófono).
  Future<void> _cargarAjustes() async {
    final a = await ServicioAjustes.cargar();
    await _voz.inicializar(
        tono: a.tono, velocidad: a.velocidad, idioma: a.idiomaVoz);
    _comandos
      ..soloDispositivo = a.reconocimientoSoloDispositivo
      ..localeId = a.idiomaReconocimiento;
    if (mounted) setState(() => _vozActiva = a.vozActiva);
  }

  /// El teléfono no puede reconocer voz sin internet: se apagan los comandos.
  void _alFallarComandosEnDispositivo() {
    if (!mounted) return;
    setState(() => _comandosActivos = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tu teléfono no reconoce voz sin internet. '
          'Puedes permitirlo en Ajustes > Privacidad.'),
      duration: Duration(seconds: 5),
    ));
  }

  /// Activa/desactiva los comandos de voz.
  Future<void> _toggleComandos() async {
    if (!_sttDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El reconocimiento de voz no está disponible'),
        ),
      );
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
    if (!_entrenando) {
      await _comandos.escuchar(
        comandos: const [
          'empezar',
          'empezamos',
          'inicio',
          'iniciar',
          'vamos',
          'comenzar',
        ],
        alDetectar: (_) {
          if (_entreno.encuadreOk && !_entrenando) _empezar();
        },
      );
    } else {
      await _comandos.escuchar(
        comandos: const [
          'fin',
          'finalizar',
          'finalizo',
          'terminar',
          'termina',
          'terminamos',
        ],
        alDetectar: (_) {
          if (!_guardando) _finalizar();
        },
      );
    }
  }

  // ===========================================================================
  // CÁMARA (Fase A: sin cambios)
  // ===========================================================================

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
  /// stream. Se reutiliza al cambiar de cámara y al volver de segundo plano.
  Future<void> _crearControlador(CameraDescription camara) async {
    _camaraActiva = camara;
    final generacion = ++_generacionCamara;
    final controlador = CameraController(
      camara,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await controlador.initialize();
      // Si mientras inicializaba se cerró la pantalla o se pidió otra
      // cámara, este controlador ya no sirve: lo liberamos.
      if (!mounted || generacion != _generacionCamara) {
        await _liberarControlador(controlador);
        return;
      }
      await _arrancarStream(controlador, generacion);
      setState(() {
        _controlador = controlador;
        _inicializando = false;
        _cambiandoCamara = false;
      });
    } catch (e) {
      await _liberarControlador(controlador);
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo iniciar la cámara: $e';
        _inicializando = false;
        _cambiandoCamara = false;
      });
    }
  }

  /// Arranca el stream de imágenes "marcado" con su generación.
  Future<void> _arrancarStream(CameraController controlador, int generacion) {
    return controlador.startImageStream(
      (imagen) => _procesarFrame(imagen, generacion),
    );
  }

  /// Detiene el stream y libera un controlador sin lanzar errores.
  Future<void> _liberarControlador(CameraController? controlador) async {
    if (controlador == null) return;
    try {
      if (controlador.value.isStreamingImages) {
        await controlador.stopImageStream();
      }
    } catch (_) {}
    try {
      await controlador.dispose();
    } catch (_) {}
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

    // 1) Sacamos el controlador de la UI ANTES de liberarlo: así
    //    CameraPreview nunca se dibuja con un controlador destruido.
    final anterior = _controlador;
    _generacionCamara++; // invalida los frames en vuelo de la cámara vieja
    setState(() {
      _cambiandoCamara = true;
      _controlador = null;
      _resultado = null; // el esqueleto viejo tenía otra rotación/espejo
    });
    if (_entrenando) _entreno.pausar();

    // 2) Liberamos la cámara vieja y 3) creamos la nueva.
    await _liberarControlador(anterior);
    if (!mounted) return;
    await _crearControlador(nueva.first);
  }

  /// Libera la cámara al pasar a segundo plano y la recupera al volver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.paused) {
      final actual = _controlador;
      if (actual == null) return;
      _camaraLiberada = true;
      _generacionCamara++;
      setState(() {
        _controlador = null;
        _resultado = null;
      });
      if (_entrenando) _entreno.pausar();
      if (_comandosActivos) _comandos.pausar();
      _voz.callar();
      _liberarControlador(actual);
    } else if (estado == AppLifecycleState.resumed) {
      WakelockPlus.enable(); // el sistema pudo haberlo soltado
      if (_camaraLiberada && _camaraActiva != null && !_guardando) {
        _camaraLiberada = false;
        _crearControlador(_camaraActiva!);
        if (_comandosActivos) _comandos.reanudar();
      }
    }
  }

  // ===========================================================================
  // PROCESAMIENTO DE FRAMES
  // ===========================================================================

  Future<void> _procesarFrame(CameraImage imagen, int generacion) async {
    // Descarta frames de una cámara que ya no está activa.
    if (_procesando || generacion != _generacionCamara) return;
    final controlador = _controlador;
    final camara = _camaraActiva;
    if (controlador == null || camara == null) return;
    _procesando = true;
    try {
      final resultado = await _detectorPose.procesarFrame(
        imagen: imagen,
        controlador: controlador,
        camara: camara,
      );
      // Mientras ML Kit procesaba, pudo cambiar la cámara o cerrarse la
      // pantalla: en ese caso este resultado ya no vale.
      if (!mounted || generacion != _generacionCamara) return;

      // Toda la lógica (encuadre, cuenta regresiva, conteo, coaching,
      // pausa automática) está en el controlador.
      final estabaEntrenando = _entrenando;
      final pose = resultado.poses.isEmpty ? null : resultado.poses.first;
      final anuncio = _entreno.procesar(pose, DateTime.now());
      _anunciar(anuncio);
      if (!estabaEntrenando && _entrenando) _alEmpezarEntrenamiento();

      setState(() => _resultado = resultado);
    } catch (e) {
      debugPrint('Error procesando frame: $e');
    } finally {
      _procesando = false;
    }
  }

  /// Dice en voz alta lo que decidió el controlador (si la voz está activa).
  void _anunciar(Anuncio? anuncio) {
    if (anuncio == null || !_vozActiva) return;
    _voz.decirCoach(anuncio.texto, interrumpir: anuncio.prioritario);
  }

  // ===========================================================================
  // ACCIONES
  // ===========================================================================

  /// Botón "Empezar" o comando de voz: empieza ya, sin cuenta regresiva.
  void _empezar() {
    if (!_entreno.empezar(DateTime.now())) return;
    _alEmpezarEntrenamiento();
    _anunciar(const Anuncio('¡Vamos!', prioritario: true));
    setState(() {});
  }

  /// Se llama al pasar a "Entrenando" (por botón, voz o cuenta regresiva).
  void _alEmpezarEntrenamiento() {
    _voz.reiniciar();
    _mostrarTips = false;
    // Cambia las palabras clave: ahora escuchamos "finalizar".
    _escucharFaseActual();
  }

  void _reiniciar() {
    _entreno.reiniciarSerie(DateTime.now());
    _voz.reiniciar();
    setState(() {});
  }

  void _toggleVoz() {
    setState(() => _vozActiva = !_vozActiva);
    if (!_vozActiva) _voz.callar(); // corta lo que esté diciendo
  }

  Future<void> _finalizar() async {
    setState(() => _guardando = true);
    _procesando = true;
    _voz.callar();
    try {
      await _controlador?.stopImageStream();
    } catch (_) {}

    final duracion = _entreno.duracionSegundos(DateTime.now());
    try {
      final resultado = await _servicioSesiones.guardarSesion(
        ejercicioId: widget.receta.id,
        iniciada: _entreno.inicio,
        repsTotales: _entreno.repsTotales,
        repsCorrectas: _entreno.repsCorrectas,
        repsIncorrectas: _entreno.repsIncorrectas,
        duracionSegundos: duracion,
        repeticiones: _entreno.reps,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaResumen(
            camaras: widget.camaras,
            receta: widget.receta,
            repsTotales: _entreno.repsTotales,
            repsCorrectas: _entreno.repsCorrectas,
            repsIncorrectas: _entreno.repsIncorrectas,
            duracionSegundos: duracion,
            repeticiones: _entreno.reps,
            pendienteDeSubir: resultado == ResultadoGuardado.pendiente,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      _procesando = false;
      setState(() => _guardando = false);
      try {
        final actual = _controlador;
        if (actual != null) await _arrancarStream(actual, _generacionCamara);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable(); // fuera de esta pantalla, comportamiento normal
    // El resto de la app está diseñado en vertical.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _generacionCamara++; // ningún frame en vuelo debe tocar el estado
    _liberarControlador(_controlador);
    _detectorPose.cerrar();
    _voz.cerrar();
    _comandos.cerrar();
    super.dispose();
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colores.oscuro, body: _contenido());
  }

  Widget _contenido() {
    if (_inicializando) {
      return const Center(
        child: CircularProgressIndicator(color: Colores.acento),
      );
    }
    if (!_permisoConcedido) return _vistaPermiso();
    if (_error != null) return _vistaError();

    final ahora = DateTime.now();
    final horizontal =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final numeroCuenta = _entreno.numeroCuenta(ahora);

    return Stack(
      // Todas las capas son Positioned: con "expand" el Stack siempre ocupa
      // toda la pantalla (si no, un hijo de tamaño 0 lo encogía a 0x0).
      fit: StackFit.expand,
      children: [
        _preview(ahora),
        if (!_entrenando) _siluetaGuia(horizontal),
        if (_entrenando)
          Positioned.fill(
            child: DestelloVeredicto(
              idVeredicto: _entreno.coach.idVeredicto,
              correcto: _entreno.coach.ultimoVeredictoCorrecto ?? true,
            ),
          ),
        if (numeroCuenta != null) _cuentaRegresiva(numeroCuenta),
        if (_entreno.pausado) _velaPausa(),
        _barraSuperior(),
        if (!_entrenando && _sugerirGirar(horizontal))
          _avisoOrientacion(horizontal),
        if (_entrenando && !_entreno.pausado) _hudContador(horizontal),
        _panelInferior(ahora, horizontal),
        if (_cambiandoCamara)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(
                child: CircularProgressIndicator(color: Colores.acento),
              ),
            ),
          ),
      ],
    );
  }

  Widget _preview(DateTime ahora) {
    final controlador = _controlador;
    final resultado = _resultado;
    // Durante el cambio de cámara (o en segundo plano) no hay controlador:
    // mostramos fondo oscuro; el spinner de _cambiandoCamara va encima.
    if (controlador == null || !controlador.value.isInitialized) {
      return const Positioned.fill(child: ColoredBox(color: Colores.oscuro));
    }
    return Positioned.fill(
      child: Center(
        child: CameraPreview(
          controlador,
          child: resultado == null
              ? const SizedBox.shrink()
              : CustomPaint(
                  painter: PintorEsqueleto(
                    poses: resultado.poses,
                    tamanoImagen: resultado.tamanoImagen,
                    rotacion: resultado.rotacion,
                    lente: _camaraActiva!.lensDirection,
                    formaCorrecta: _entreno.formaCorrecta(ahora),
                    articulacionesResaltadas: _entreno.resaltadas(ahora),
                  ),
                ),
        ),
      ),
    );
  }

  /// Silueta semitransparente en la posición inicial: muestra DÓNDE y CÓMO
  /// ponerse. Se desvanece al quedar encuadrado.
  Widget _siluetaGuia(bool horizontal) {
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Padding(
            // Deja libre la barra superior y el panel inferior.
            padding: horizontal
                ? const EdgeInsets.fromLTRB(24, 56, 420, 16)
                : const EdgeInsets.fromLTRB(24, 64, 24, 250),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _entreno.encuadreOk ? 0 : 0.55,
              child: FiguraEstatica(
                pose: _guia.poseInicial,
                color: Colors.white,
                colorPuntos: Colores.acento,
                grosor: 0.025,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Número grande de la cuenta regresiva.
  Widget _cuentaRegresiva(int numero) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Container(
              key: ValueKey(numero),
              width: 150,
              height: 150,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colores.oscuro.withValues(alpha: 0.75),
                shape: BoxShape.circle,
                border: Border.all(color: Colores.acento, width: 4),
              ),
              child: Text(
                '$numero',
                style: Tipografia.sora(
                  80,
                  peso: FontWeight.w800,
                  color: Colors.white,
                  altura: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Velo de pausa automática.
  Widget _velaPausa() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_filled_rounded,
                    color: Colors.white, size: 64),
                const SizedBox(height: 12),
                Text('En pausa',
                    style: Tipografia.sora(26,
                        peso: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Vuelve al cuadro para continuar',
                    style: Tipografia.manrope(15,
                        peso: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sugerencia (no obligatoria) si la orientación del teléfono no es la
  /// que mejor funciona para este ejercicio.
  bool _sugerirGirar(bool horizontal) =>
      (widget.receta.orientacion == OrientacionSugerida.horizontal) !=
      horizontal;

  Widget _avisoOrientacion(bool horizontal) {
    final sugiereHorizontal =
        widget.receta.orientacion == OrientacionSugerida.horizontal;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colores.oscuro.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.screen_rotation_rounded,
                      color: Colores.acento, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    sugiereHorizontal
                        ? 'Tip: gira el teléfono en horizontal'
                        : 'Tip: este ejercicio va mejor en vertical',
                    style: Tipografia.manrope(13,
                        peso: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Barra superior: volver · nombre · (reiniciar) · micrófono · cámara · voz
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
              _botonCircular(
                Icons.close_rounded,
                () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.receta.nombre,
                  style: Tipografia.sora(
                    14,
                    peso: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              if (_entrenando)
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

  Widget _botonCircular(
    IconData icono,
    VoidCallback onTap, {
    bool activo = false,
  }) {
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
                : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  /// Contador grande. El número principal son las reps CORRECTAS: solo
  /// "vale" la rep bien hecha. Las que hay que corregir van aparte, en pequeño.
  /// En horizontal se coloca arriba a la izquierda y más compacto.
  Widget _hudContador(bool horizontal) {
    final aCorregir = _entreno.repsIncorrectas;
    final contenido = Column(
      crossAxisAlignment:
          horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          _esIsometrico ? 'TIEMPO EN POSICIÓN' : 'REPS CORRECTAS',
          style: Tipografia.manrope(
            12,
            peso: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        SizedBox(
          height: horizontal ? 64 : 92,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _esIsometrico
                  ? '${_entreno.segundos.toStringAsFixed(0)}s'
                  : '${_entreno.repsCorrectas}',
              style: Tipografia.sora(
                88,
                peso: FontWeight.w800,
                color: Colors.white,
                altura: 1,
              ),
            ),
          ),
        ),
        if (!_esIsometrico) ...[
          const SizedBox(height: 6),
          TiraRepeticiones(veredictos: _entreno.coach.veredictos),
          if (aCorregir > 0) ...[
            const SizedBox(height: 8),
            _pill('$aCorregir a corregir', Colores.acento),
          ],
        ],
      ],
    );

    return Positioned(
      top: 0,
      left: 0,
      right: horizontal ? null : 0,
      child: SafeArea(
        child: Padding(
          padding: horizontal
              ? const EdgeInsets.only(top: 60, left: 20)
              : const EdgeInsets.only(top: 66),
          child: contenido,
        ),
      ),
    );
  }

  Widget _pill(String texto, Color punto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: punto, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: Tipografia.manrope(
              13,
              peso: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Panel inferior: abajo a lo ancho (vertical) o abajo a la derecha
  /// (horizontal, para no tapar el cuerpo).
  Widget _panelInferior(DateTime ahora, bool horizontal) {
    final contenido = _entrenando
        ? _controlesEntrenando(ahora, horizontal)
        : _controlesPreparando(ahora, horizontal);
    return Positioned(
      left: horizontal ? null : 0,
      right: 0,
      bottom: 0,
      width: horizontal ? 400 : null,
      child: SafeArea(
        top: false,
        left: !horizontal,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: contenido,
        ),
      ),
    );
  }

  // --- Fase Prepárate (incluye la cuenta regresiva) ---
  Widget _controlesPreparando(DateTime ahora, bool horizontal) {
    final ok = _entreno.encuadreOk;
    final enCuenta = _entreno.enCuentaRegresiva;
    // En horizontal hay poca altura: los tips se abren solo a petición.
    final verTips = horizontal ? _mostrarTips : true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bannerPreparacion(ahora),
        if (verTips) ...[
          const SizedBox(height: 12),
          _tarjetaTips(),
        ],
        if (horizontal) _botonTips(),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ok ? _empezar : null,
          style: FilledButton.styleFrom(
            backgroundColor: ok ? Colores.acento : const Color(0xFF3A352F),
            foregroundColor: ok ? Colores.sobreAcento : Colors.white54,
            minimumSize: const Size.fromHeight(Medidas.alturaBoton),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Medidas.radioBoton),
            ),
          ),
          child: Text(enCuenta
              ? 'Empezar ya'
              : (ok ? 'Empezar' : 'Colócate como la silueta')),
        ),
      ],
    );
  }

  /// Banner de "Prepárate": guía -> quédate quieto (con progreso) -> cuenta.
  Widget _bannerPreparacion(DateTime ahora) {
    final ok = _entreno.encuadreOk;
    final enCuenta = _entreno.enCuentaRegresiva;
    final progreso = _entreno.progresoAutoInicio(ahora);

    final String texto;
    final IconData icono;
    if (enCuenta) {
      texto = '¡Prepárate! Empezamos…';
      icono = Icons.timer_rounded;
    } else if (ok) {
      texto = '¡Perfecto! Quédate quieto un momento';
      icono = Icons.check_circle_rounded;
    } else {
      texto = widget.receta.vista == VistaCamara.lateral
          ? 'Ponte de perfil, como la silueta'
          : 'Ponte de frente, como la silueta';
      icono = Icons.center_focus_weak_rounded;
    }
    final fondo = ok ? Colores.okFuerte : Colores.acento;
    final colorTexto = ok ? Colors.white : Colores.sobreAcento;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icono, color: colorTexto, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  style: Tipografia.manrope(
                    14,
                    peso: FontWeight.w700,
                    color: colorTexto,
                  ),
                ),
              ),
            ],
          ),
          if (ok && !enCuenta) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 5,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonTips() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _mostrarTips = !_mostrarTips),
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: Text(
          _mostrarTips ? 'Ocultar' : '¿Cómo me coloco?',
          style: Tipografia.manrope(13, peso: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _tarjetaTips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cómo colocarte',
            style: Tipografia.manrope(
              12,
              peso: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          ..._guia.colocacion.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 10),
                    child: Icon(
                      Icons.radio_button_checked,
                      color: Colores.acento,
                      size: 14,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t,
                      style: Tipografia.manrope(
                        13.5,
                        color: Colors.white,
                        altura: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Fase Entrenando ---
  Widget _controlesEntrenando(DateTime ahora, bool horizontal) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_mostrarTips) ...[_tarjetaTips(), const SizedBox(height: 10)],
        if (!_entreno.pausado) BannerCoach(mensaje: _entreno.mensaje(ahora)),
        const SizedBox(height: 4),
        _botonTips(),
        FilledButton(
          onPressed: _guardando ? null : _finalizar,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colores.oscuro,
            minimumSize: const Size.fromHeight(Medidas.alturaBoton),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Medidas.radioBoton),
            ),
          ),
          child: _guardando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colores.oscuro,
                  ),
                )
              : const Text('Terminar entrenamiento'),
        ),
      ],
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
            const Icon(
              Icons.videocam_off_rounded,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Necesitamos tu cámara',
              style: Tipografia.sora(20, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Actívala para analizar tu técnica. El video nunca sale del teléfono.',
              style: Tipografia.manrope(14, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: openAppSettings,
              child: const Text('Abrir ajustes'),
            ),
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
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Ocurrió un error',
              style: Tipografia.manrope(15, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}