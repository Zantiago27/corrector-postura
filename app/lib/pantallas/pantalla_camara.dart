import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/geometria.dart';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../ml/detector_pose.dart';
import 'pintor_esqueleto.dart';

class PantallaCamara extends StatefulWidget {
  final List<CameraDescription> camaras;

  const PantallaCamara({super.key, required this.camaras});

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
  double _anguloRodilla = 0; // verificación temporal de la geometría

  @override
  void initState() {
    super.initState();
    _iniciarCamara();
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
      // Cálculo temporal del ángulo de la rodilla derecha (solo para verificar).
      double angulo = 0;
      if (resultado.poses.isNotEmpty) {
        final pose = resultado.poses.first;
        final cadera = punto(pose, PoseLandmarkType.rightHip);
        final rodilla = punto(pose, PoseLandmarkType.rightKnee);
        final tobillo = punto(pose, PoseLandmarkType.rightAnkle);
        if (cadera != null && rodilla != null && tobillo != null) {
          angulo = calcularAngulo(cadera, rodilla, tobillo);
        }
      }
      if (mounted) {
        setState(() {
          _resultado = resultado;
          _anguloRodilla = angulo;
        });
      }
    } catch (e) {
      debugPrint('Error procesando frame: $e');
    } finally {
      _procesando = false;
    }
  }

  @override
  void dispose() {
    _detectorPose.cerrar();
    _controlador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara')),
      body: _construirCuerpo(),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.black54,
            child: Text(
              'Rodilla: ${_anguloRodilla.toStringAsFixed(0)}°',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}
