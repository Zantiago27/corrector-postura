import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

//import '../core/geometria.dart';
//import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

//nuevos imports
//import '../ejercicios/sentadilla.dart';
import '../core/motor_ejercicio.dart';
import '../ejercicios/receta_ejercicio.dart';

import '../ml/detector_pose.dart';
import 'pintor_esqueleto.dart';

//servicio de voz
import '../servicios/servicio_voz.dart';

//supabase
//import 'package:supabase_flutter/supabase_flutter.dart';
import '../servicios/servicio_sesiones.dart';

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
  String? _error;

  bool _procesando = false;
  ResultadoPose? _resultado; // última pose detectada
  //double _anguloRodilla = 0; // verificación temporal de la geometría

  //final MotorEjercicio _motor = MotorEjercicio(recetaSentadilla);
  late final MotorEjercicio _motor; //(ahora se crea con la receta que llega de afuera, así que se inicializa en initState
  final ServicioVoz _voz = ServicioVoz(); //servicio de voz

  int _repeticiones = 0;
  double _anguloActual = 0;
  FaseMovimiento _fase = FaseMovimiento.arriba;
  List<ReglaForma> _errores = [];
  double _segundos = 0;
  bool _formaCorrecta = true;

  //para guardar datos
  final ServicioSesiones _servicioSesiones = ServicioSesiones();
  final List<RepeticionCompletada> _repsCompletadas = [];
  late DateTime _inicio;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _motor = MotorEjercicio(widget.receta);
    _inicio = DateTime.now();
    _iniciarCamara();
    _voz.inicializar();
  }

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
    _camaraActiva = camaraFrontal;

    final controlador = CameraController(
      camaraFrontal,
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
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo iniciar la cámara: $e';
        _inicializando = false;
      });
    }
  }

  Future<void> _procesarFrame(CameraImage imagen) async {
    if (_procesando) return;
    _procesando = true;
    try {
      final resultado = await _detectorPose.procesarFrame(
        imagen: imagen,
        controlador: _controlador!,
        camara: _camaraActiva!,
      );
      //if (mounted) setState(() => _resultado = resultado);
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

          //nuevo
          _segundos = evaluacion.segundosMantenidos;
          _formaCorrecta = evaluacion.formaCorrecta;

          //logica de voz
          // Feedback por voz: prioriza el error más grave;
          // si no hay errores y se completó una rep, anuncia el número.
          if (_errores.isNotEmpty) {
            final graves = _errores.where((e) => e.severidad == Severidad.alta);
            _voz.decir(
              (graves.isNotEmpty ? graves.first : _errores.first).mensaje,
            );
          } else if (_repeticiones > repsAntes) {
            _voz.decirNumero(_repeticiones);
          }
        } else {
          _errores = [];
          _motor.pausar();
        }
      } else {
        _errores = [];
      }
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      debugPrint('Error procesando frame: $e');
    } finally {
      _procesando = false;
    }
  }

  //metodos para reiniciar y finalizar sesion
  void _reiniciar() {
    _motor.reiniciar();
    _voz.reiniciar();
    _segundos = 0;
    _repsCompletadas.clear();
    _inicio = DateTime.now();
    setState(() => _repeticiones = 0);
  }

  Future<void> _finalizar() async {
    setState(() => _guardando = true);
    _procesando = true; // frena el procesamiento de nuevos frames
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
        duracionSegundos: _segundos.round(), // relevante en la plancha
        repeticiones: _repsCompletadas,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesión guardada ✓')));
      Navigator.of(context).pop(); // vuelve al menú
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      _procesando = false;
      setState(() => _guardando = false);
      try {
        await _controlador?.startImageStream(_procesarFrame); // reanuda
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _detectorPose.cerrar();
    _voz.cerrar();
    _controlador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receta.nombre),
        actions: [
          IconButton(
            tooltip: 'Reiniciar',
            icon: const Icon(Icons.refresh),
            onPressed: _reiniciar,
          ),
        ],
      ),
      body: _construirCuerpo(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _guardando ? null : _finalizar,
        icon: _guardando
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check),
        label: Text(_guardando ? 'Guardando...' : 'Finalizar'),
      ),
    );
  }

  Widget _construirCuerpo() {
    if (_inicializando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_permisoConcedido) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Se necesita permiso de cámara para usar la app. '
            'Actívalo desde los ajustes del teléfono.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    // Preview con el esqueleto dibujado encima.
    // Preview con el esqueleto y el ángulo de la rodilla encima.
    return Stack(
      children: [
        Center(
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
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.receta.tipo == TipoEjercicio.isometrico
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiempo: ${_segundos.toStringAsFixed(0)} s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formaCorrecta
                            ? 'Postura correcta'
                            : 'Corrige la postura',
                        style: TextStyle(
                          color: _formaCorrecta
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reps: $_repeticiones',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Ángulo: ${_anguloActual.toStringAsFixed(0)}°  ·  '
                        '${_fase == FaseMovimiento.abajo ? "ABAJO" : "ARRIBA"}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        // Banner de errores de forma (abajo de la pantalla).
        if (_errores.isNotEmpty)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _errores.map((e) {
                final color = e.severidad == Severidad.alta
                    ? Colors.redAccent
                    : Colors.orangeAccent;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    e.mensaje,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
