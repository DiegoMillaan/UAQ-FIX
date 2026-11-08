import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'api_service.dart';
import 'main.dart';

class ArWorkspaceScreen extends StatefulWidget {
  final String ubicacionQr;
  final String nombreZona;
  final UserSession session;

  const ArWorkspaceScreen({
    super.key,
    required this.ubicacionQr,
    this.nombreZona = "Espacio AR",
    required this.session,
  });

  @override
  State<ArWorkspaceScreen> createState() => _ArWorkspaceScreenState();
}

class _ArWorkspaceScreenState extends State<ArWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _camaraLista = false;
  bool _cerrandoPantalla = false;

  List<ReporteMap> _pinesActivos = [];
  bool _cargandoPines = true;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  vm.Vector3 _wx = vm.Vector3(1.0, 0.0, 0.0);
  vm.Vector3 _wy = vm.Vector3(0.0, 1.0, 0.0);
  vm.Vector3 _wz = vm.Vector3(0.0, 0.0, 1.0);

  bool _orientacionInicializada = false;
  bool _brujulaCalibrada = false;
  DateTime? _ultimoEventoGyro;

  vm.Vector3 _gravDev = vm.Vector3(0.0, 9.81, 0.0);
  vm.Vector3 _magDev = vm.Vector3.zero();

  double _magRefCos = 1.0;
  double _magRefSin = 0.0;

  double _offsetRadialPasos = 0.0;
  double _gravMagSuave = 9.81;
  DateTime _ultimoPaso = DateTime.now();

  final Map<String, Offset> _posSuavizadaPorPin = {};
  static const double _tanHalfFovH = 0.498;

  Offset? _puntoTemporalPantalla;
  late AnimationController _pinPulseController;

  @override
  void initState() {
    super.initState();
    _pinPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _inicializarCamara();
    _iniciarMotor9DOF();
    _cargarPinesDesdeAWS();
  }

  Future<void> _inicializarCamara() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final controller = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await controller.initialize();
        if (mounted && !_cerrandoPantalla) {
          setState(() {
            _cameraController = controller;
            _camaraLista = true;
          });
        } else {
          await controller.dispose();
        }
      }
    } catch (e) {
      debugPrint("Aviso cámara AR: $e");
    }
  }

  Future<void> _salirDePantallaAR() async {
    if (_cerrandoPantalla) return;
    setState(() {
      _cerrandoPantalla = true;
      _camaraLista = false;
    });

    _gyroSub?.cancel();
    _accelSub?.cancel();
    _magSub?.cancel();

    try {
      final cam = _cameraController;
      _cameraController = null;
      await cam?.dispose();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _alinearEjesConGravedadActual() {
    if (_gravDev.length < 2.0) return;
    _wy = _gravDev.normalized();

    vm.Vector3 forwardCam = vm.Vector3(0.0, 0.0, -1.0);
    if (_wy.dot(forwardCam).abs() > 0.92) {
      forwardCam = vm.Vector3(0.0, 1.0, 0.0);
    }
    _wx = forwardCam.cross(_wy).normalized();
    _wz = _wx.cross(_wy).normalized();
    _orientacionInicializada = true;
    _brujulaCalibrada = false;
  }

  void _ortonormalizarBase() {
    _wy.normalize();
    _wx = (_wx - _wy * _wx.dot(_wy)).normalized();
    _wz = _wx.cross(_wy).normalized();
  }

  vm.Vector3 _rotarVectorRodrigues(
      vm.Vector3 v, vm.Vector3 kUnit, double sinPhi, double cosPhi) {
    final double dot = kUnit.dot(v);
    return (v * cosPhi) +
        (kUnit.cross(v) * sinPhi) +
        (kUnit * (dot * (1.0 - cosPhi)));
  }

  void _iniciarMotor9DOF() {
    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((MagnetometerEvent event) {
      final vm.Vector3 lectura = vm.Vector3(event.x, event.y, event.z);
      final double mag = lectura.length;
      if (mag < 12.0 || mag > 110.0) return;

      if (_magDev.length == 0.0) {
        _magDev = lectura;
      } else {
        _magDev = _magDev * 0.85 + lectura * 0.15;
      }

      if (_orientacionInicializada && !_brujulaCalibrada) {
        final vm.Vector3 eastMag = _magDev.cross(_wy);
        if (eastMag.length > 2.0) {
          eastMag.normalize();
          final vm.Vector3 southMag = eastMag.cross(_wy).normalized();
          _magRefCos = _wx.dot(eastMag);
          _magRefSin = _wx.dot(southMag);
          _brujulaCalibrada = true;
        }
      }
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((AccelerometerEvent event) {
      final vm.Vector3 lectura = vm.Vector3(event.x, event.y, event.z);
      final double mag = lectura.length;
      if (mag < 1.0) return;

      _gravDev = _gravDev * 0.88 + lectura * 0.12;

      if (!_orientacionInicializada && _gravDev.length > 5.0) {
        _alinearEjesConGravedadActual();
      }

      _gravMagSuave = _gravMagSuave * 0.75 + mag * 0.25;
      final double impulsoPaso = _gravMagSuave - 9.81;
      final ahora = DateTime.now();

      if (impulsoPaso > 1.85 &&
          ahora.difference(_ultimoPaso).inMilliseconds > 520) {
        _ultimoPaso = ahora;
        final double accelZLineal = event.z - (9.81 * _wy.z);
        final double deltaPaso = accelZLineal >= 0 ? -0.35 : 0.35;
        setState(() {
          _offsetRadialPasos =
              (_offsetRadialPasos + deltaPaso).clamp(-3.5, 4.5);
        });
      }
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((GyroscopeEvent event) {
      final ahora = DateTime.now();
      if (_ultimoEventoGyro == null) {
        _ultimoEventoGyro = ahora;
        return;
      }

      final double dt =
          ahora.difference(_ultimoEventoGyro!).inMicroseconds / 1000000.0;
      _ultimoEventoGyro = ahora;

      if (dt <= 0.0 || dt > 0.2 || !_orientacionInicializada) return;

      final double gx = event.x.abs() > 0.003 ? event.x : 0.0;
      final double gy = event.y.abs() > 0.003 ? event.y : 0.0;
      final double gz = event.z.abs() > 0.003 ? event.z : 0.0;

      vm.Vector3 omega = vm.Vector3(gx, gy, gz);

      final double gravNorm = _gravDev.length;
      if ((gravNorm - 9.81).abs() < 1.8) {
        final vm.Vector3 uAccel = _gravDev / gravNorm;
        final vm.Vector3 errorGrav = uAccel.cross(_wy);
        omega += errorGrav * 2.2;
      }

      if (_brujulaCalibrada && _magDev.length > 10.0) {
        final vm.Vector3 eastMag = _magDev.cross(_wy);
        if (eastMag.length > 2.0) {
          eastMag.normalize();
          final vm.Vector3 southMag = eastMag.cross(_wy).normalized();
          final vm.Vector3 wxMag =
              (eastMag * _magRefCos) + (southMag * _magRefSin);
          final vm.Vector3 errorMag = _wy * _wy.dot(wxMag.cross(_wx));
          omega += errorMag * 0.85;
        }
      }

      final vm.Vector3 thetaVec = -omega * dt;
      final double phi = thetaVec.length;

      if (phi > 0.00001) {
        final vm.Vector3 kUnit = thetaVec / phi;
        final double sinPhi = math.sin(phi);
        final double cosPhi = math.cos(phi);

        _wx = _rotarVectorRodrigues(_wx, kUnit, sinPhi, cosPhi);
        _wy = _rotarVectorRodrigues(_wy, kUnit, sinPhi, cosPhi);
        _wz = _rotarVectorRodrigues(_wz, kUnit, sinPhi, cosPhi);
        _ortonormalizarBase();

        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void _recalibrarOrigenEspacial() {
    setState(() {
      _alinearEjesConGravedadActual();
      _offsetRadialPasos = 0.0;
      _posSuavizadaPorPin.clear();
    });
    _mostrarNotificacion(
      icono: Icons.center_focus_strong_rounded,
      texto: "Espacio AR recalibrado a tu vista actual",
      color: UaqFixApp.primaryBlue,
    );
  }

  vm.Vector3 _dispositivoAMundo(vm.Vector3 vDev) {
    return vm.Vector3(
      _wx.dot(vDev),
      _wy.dot(vDev),
      _wz.dot(vDev),
    );
  }

  vm.Vector3 _mundoADispositivo(double worldX, double worldY, double worldZ) {
    return (_wx * worldX) + (_wy * worldY) + (_wz * worldZ);
  }

  vm.Vector3 _calcularRayoMundoEnToque(Offset posicionToque, Size screenSize) {
    final double focalPx = (screenSize.width / 2.0) / _tanHalfFovH;
    final double xDev = (posicionToque.dx - screenSize.width / 2.0) / focalPx;
    final double yDev = (screenSize.height / 2.0 - posicionToque.dy) / focalPx;
    final vm.Vector3 rayDev = vm.Vector3(xDev, yDev, -1.0).normalized();

    return _dispositivoAMundo(rayDev).normalized();
  }

  double _estimarDistanciaAutomatica(vm.Vector3 rayoMundo) {
    if (rayoMundo.y < -0.15) {
      final double distPiso = (1.3 / (-rayoMundo.y)).clamp(0.5, 4.0);
      return double.parse(distPiso.toStringAsFixed(1));
    }
    return 1.5;
  }

  ReporteMap _proyectarPinAPantalla(
    String reporteId,
    double worldX,
    double worldY,
    double worldZ,
    Size screenSize,
  ) {
    final double distanciaBase =
        math.sqrt(worldX * worldX + worldY * worldY + worldZ * worldZ)
            .clamp(0.35, 25.0);

    final double distanciaEfectiva =
        (distanciaBase + _offsetRadialPasos).clamp(0.35, 25.0);

    final vm.Vector3 posCam = _mundoADispositivo(worldX, worldY, worldZ);
    final double focalPx = (screenSize.width / 2.0) / _tanHalfFovH;

    final bool frenteACamara = posCam.z < -0.08;
    double dx = -9999.0;
    double dy = -9999.0;

    if (frenteACamara) {
      final double invZ = 1.0 / (-posCam.z);
      final double rawDx =
          (screenSize.width / 2.0) + (posCam.x * invZ) * focalPx;
      final double rawDy =
          (screenSize.height / 2.0) - (posCam.y * invZ) * focalPx;

      final Offset? prev = _posSuavizadaPorPin[reporteId];
      if (prev == null) {
        dx = rawDx;
        dy = rawDy;
      } else {
        final double distPx = (Offset(rawDx, rawDy) - prev).distance;
        if (distPx < 1.8) {
          dx = prev.dx;
          dy = prev.dy;
        } else {
          final double alpha = (distPx / 28.0).clamp(0.28, 0.85);
          dx = prev.dx + (rawDx - prev.dx) * alpha;
          dy = prev.dy + (rawDy - prev.dy) * alpha;
        }
      }
      _posSuavizadaPorPin[reporteId] = Offset(dx, dy);
    } else {
      _posSuavizadaPorPin.remove(reporteId);
    }

    final bool enPantalla = frenteACamara &&
        dx >= -65.0 &&
        dx <= screenSize.width + 65.0 &&
        dy >= -65.0 &&
        dy <= screenSize.height + 65.0;

    final double deltaYaw = math.atan2(posCam.x, -posCam.z);

    return {
      "offset": Offset(dx, dy),
      "enPantalla": enPantalla,
      "deltaYaw": deltaYaw,
      "distancia": distanciaEfectiva,
    };
  }

  double _calcularEscalaPorDistancia(double distanciaMetros) {
    return (1.35 / math.pow(distanciaMetros.clamp(0.4, 8.0), 0.72))
        .clamp(0.38, 1.65);
  }

  Future<void> _cargarPinesDesdeAWS() async {
    setState(() => _cargandoPines = true);
    try {
      final pines = await ApiService.obtenerPinesAR(widget.ubicacionQr);
      if (mounted) {
        setState(() {
          _pinesActivos = pines;
          _cargandoPines = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoPines = false);
        _mostrarNotificacion(
          icono: Icons.cloud_off_rounded,
          texto: "No se pudo sincronizar con AWS",
          color: const Color(0xFFDC2626),
        );
      }
    }
  }

  void _mostrarNotificacion({
    required IconData icono,
    required String texto,
    required Color color,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        elevation: 6,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
        ),
        content: Row(
          children: [
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  color: UaqFixApp.textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _magSub?.cancel();
    _pinPulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Color _colorPorTipo(String? tipo) {
    switch (tipo) {
      case 'Riesgo Crítico (Industria 4.0)':
        return const Color(0xFFDC2626);
      case 'Eléctrico / Sensores IoT':
        return const Color(0xFFD97706);
      case 'Redes / Cómputo':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF0D9488);
    }
  }

  IconData _iconoPorTipo(String? tipo) {
    switch (tipo) {
      case 'Riesgo Crítico (Industria 4.0)':
        return Icons.report_problem_rounded;
      case 'Eléctrico / Sensores IoT':
        return Icons.bolt_rounded;
      case 'Redes / Cómputo':
        return Icons.router_rounded;
      default:
        return Icons.handyman_rounded;
    }
  }

  void _mostrarFormularioNuevoPin(Offset toque, Size screenSize) {
    final vm.Vector3 rayoCongelado =
        _calcularRayoMundoEnToque(toque, screenSize);
    double distanciaMetros = _estimarDistanciaAutomatica(rayoCongelado);

    String tipoSeleccionado = 'Redes / Cómputo';
    final TextEditingController descController = TextEditingController();
    bool enviando = false;

    setState(() => _puntoTemporalPantalla = toque);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final vm.Vector3 posFinal = rayoCongelado * distanciaMetros;
            final double x = double.parse(posFinal.x.toStringAsFixed(2));
            final double y = double.parse(posFinal.y.toStringAsFixed(2));
            final double z = double.parse(posFinal.z.toStringAsFixed(2));
            final double previewScale =
                _calcularEscalaPorDistancia(distanciaMetros);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 14,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Encabezado con Expanded para eliminar el overflow de 29px
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: UaqFixApp.lightBlueBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add_location_alt_rounded,
                            color: UaqFixApp.primaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Nuevo Reporte AR",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: UaqFixApp.textDark,
                                ),
                              ),
                              Text(
                                "Autor: ${widget.session.nombre}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: UaqFixApp.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: UaqFixApp.lightBlueBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "X:$x Y:$y Z:$z",
                            style: const TextStyle(
                              color: UaqFixApp.primaryBlue,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: tipoSeleccionado,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        color: UaqFixApp.textDark,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Categoría de incidencia",
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          color: UaqFixApp.primaryBlue,
                          size: 20,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Redes / Cómputo',
                          child: Text('Redes / Cómputo'),
                        ),
                        DropdownMenuItem(
                          value: 'Eléctrico / Sensores IoT',
                          child: Text('Eléctrico / Sensores IoT'),
                        ),
                        DropdownMenuItem(
                          value: 'Infraestructura / Mobiliario',
                          child: Text('Infraestructura / Mobiliario'),
                        ),
                        DropdownMenuItem(
                          value: 'Riesgo Crítico (Industria 4.0)',
                          child: Text('Riesgo Crítico (Industria 4.0)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => tipoSeleccionado = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: UaqFixApp.backgroundSlate,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fila con Expanded para eliminar el overflow de 2.7px
                          Row(
                            children: [
                              const Icon(
                                Icons.straighten_rounded,
                                size: 18,
                                color: UaqFixApp.textMuted,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                "Distancia:",
                                style: TextStyle(
                                  color: UaqFixApp.textDark,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "${distanciaMetros.toStringAsFixed(1)} m (${distanciaMetros <= 1.0 ? 'Cerca' : distanciaMetros >= 3.5 ? 'Fondo' : 'Media'}) · Tamaño ${(previewScale * 100).round()}%",
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: UaqFixApp.primaryBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: distanciaMetros,
                            min: 0.5,
                            max: 6.0,
                            divisions: 11,
                            activeColor: UaqFixApp.primaryBlue,
                            inactiveColor: const Color(0xFFDBEAFE),
                            onChanged: (val) {
                              setModalState(() => distanciaMetros = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      style: const TextStyle(
                        color: UaqFixApp.textDark,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Descripción del desperfecto",
                        hintText: "Ej. Silla defectuosa o nodo sin red...",
                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(
                          Icons.description_outlined,
                          color: UaqFixApp.primaryBlue,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UaqFixApp.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: enviando
                            ? null
                            : () async {
                                if (descController.text.trim().isEmpty) {
                                  _mostrarNotificacion(
                                    icono: Icons.info_outline_rounded,
                                    texto: "Ingresa una breve descripción",
                                    color: UaqFixApp.primaryBlue,
                                  );
                                  return;
                                }

                                setModalState(() => enviando = true);
                                try {
                                  await ApiService.crearReporte(
                                    tipo: tipoSeleccionado,
                                    descripcion: descController.text.trim(),
                                    ubicacionQr: widget.ubicacionQr,
                                    x: x,
                                    y: y,
                                    z: z,
                                    creadoPorNombre: widget.session.nombre,
                                    creadoPorCorreo: widget.session.correo,
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  _mostrarNotificacion(
                                    icono: Icons.check_circle_outline_rounded,
                                    texto:
                                        "Pin AR anclado. Recibirás notificación cuando sea resuelto.",
                                    color: const Color(0xFF0D9488),
                                  );
                                  _cargarPinesDesdeAWS();
                                } catch (e) {
                                  setModalState(() => enviando = false);
                                  _mostrarNotificacion(
                                    icono: Icons.error_outline_rounded,
                                    texto: "Error al guardar el reporte",
                                    color: const Color(0xFFDC2626),
                                  );
                                }
                              },
                        icon: enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.push_pin_rounded, size: 18),
                        label: Text(
                          enviando
                              ? "Guardando en AWS..."
                              : "Anclar Pin en esta Ubicación",
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) {
        setState(() => _puntoTemporalPantalla = null);
      }
    });
  }

  void _mostrarDetallePin(ReporteMap pin, double distanciaActual) {
    final coords = pin['coordenadas_ar'] ?? {'x': 0, 'y': 0, 'z': -1.5};
    final color = _colorPorTipo(pin['tipo']);
    final String autorNombre =
        (pin['creado_por_nombre'] ?? 'Estudiante UAQ').toString();
    final String autorCorreo =
        (pin['creado_por_correo'] ?? 'alumnos.uaq.mx').toString();

    String accionSeleccionada = 'Reemplazo o reparación de componente';
    final TextEditingController evidenciaCtrl = TextEditingController();
    bool resolviendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_iconoPorTipo(pin['tipo']), color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pin['tipo'] ?? 'Incidencia Registrada',
                                style: const TextStyle(
                                  color: UaqFixApp.textDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Distancia al punto: ${distanciaActual.toStringAsFixed(1)} metros",
                                style: const TextStyle(
                                  color: UaqFixApp.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pin['estado'] ?? 'Pendiente',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: UaqFixApp.backgroundSlate,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Reportado por: $autorNombre ($autorCorreo)",
                            style: const TextStyle(
                              color: UaqFixApp.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            pin['descripcion'] ?? 'Sin descripción',
                            style: const TextStyle(
                              color: UaqFixApp.textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.my_location_rounded,
                                size: 14,
                                color: UaqFixApp.primaryBlue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "Coordenada 3D: X: ${coords['x']}m, Y: ${coords['y']}m, Z: ${coords['z']}m",
                                  style: const TextStyle(
                                    color: UaqFixApp.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (widget.session.esTecnico) ...[
                      const Text(
                        "Dictamen Técnico y Retroalimentación al Alumno",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: UaqFixApp.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: accionSeleccionada,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        decoration: const InputDecoration(
                          labelText: "Acción correctiva realizada",
                          prefixIcon: Icon(
                            Icons.build_circle_outlined,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Reemplazo o reparación de componente',
                            child: Text(
                              'Reemplazo o reparación de componente',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Restablecimiento de nodo / red',
                            child: Text(
                              'Restablecimiento de nodo / red',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Retiro y cambio de mobiliario dañado',
                            child: Text(
                              'Retiro y cambio de mobiliario dañado',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Aislamiento y corrección eléctrica',
                            child: Text(
                              'Aislamiento y corrección eléctrica',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setModalState(() => accionSeleccionada = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: evidenciaCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              "Evidencia / Qué se hizo para resolverlo (Obligatorio)",
                          hintText:
                              "Ej. Se retiró la silla rota del aula y se reemplazó por mobiliario nuevo...",
                          prefixIcon: Icon(
                            Icons.fact_check_outlined,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: resolviendo
                              ? null
                              : () async {
                                  if (evidenciaCtrl.text.trim().isEmpty) {
                                    _mostrarNotificacion(
                                      icono: Icons.info_outline_rounded,
                                      texto:
                                          "Describe qué se hizo para enviarle la evidencia al alumno",
                                      color: const Color(0xFFD97706),
                                    );
                                    return;
                                  }

                                  setModalState(() => resolviendo = true);
                                  try {
                                    await ApiService.resolverReporte(
                                      reporteId: pin['reporteId'],
                                      resueltoPorNombre: widget.session.nombre,
                                      resueltoPorCorreo: widget.session.correo,
                                      accionRealizada: accionSeleccionada,
                                      evidenciaResolucion:
                                          evidenciaCtrl.text.trim(),
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    _mostrarNotificacion(
                                      icono: Icons.task_alt_rounded,
                                      texto:
                                          "Reporte cerrado y notificación enviada a $autorCorreo",
                                      color: const Color(0xFF0D9488),
                                    );
                                    _cargarPinesDesdeAWS();
                                  } catch (e) {
                                    setModalState(() => resolviendo = false);
                                    _mostrarNotificacion(
                                      icono: Icons.error_outline_rounded,
                                      texto: "No se pudo resolver el reporte",
                                      color: const Color(0xFFDC2626),
                                    );
                                  }
                                },
                          icon: resolviendo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_and_archive_rounded,
                                  size: 18),
                          label: Text(
                            resolviendo
                                ? "Enviando evidencia al alumno..."
                                : "Finalizar y Enviar Retroalimentación",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: UaqFixApp.lightBlueBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: UaqFixApp.primaryBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                autorCorreo.toLowerCase() ==
                                        widget.session.correo.toLowerCase()
                                    ? "Generaste este reporte. En cuanto Mantenimiento lo repare, recibirás su evidencia en tu Centro de Notificaciones."
                                    : "Incidencia en espera de atención por parte del personal con cuenta @mantenimiento.uaq.mx.",
                                style: const TextStyle(
                                  color: UaqFixApp.primaryBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _salirDePantallaAR();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _salirDePantallaAR,
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "UAQ Fix · Visor AR",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: UaqFixApp.textDark,
                ),
              ),
              Text(
                widget.nombreZona,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: UaqFixApp.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: "Recalibrar frente (0°)",
              onPressed: _recalibrarOrigenEspacial,
              icon: const Icon(
                Icons.filter_center_focus_rounded,
                color: UaqFixApp.textDark,
                size: 21,
              ),
            ),
            IconButton(
              tooltip: "Actualizar pines",
              onPressed: _cargarPinesDesdeAWS,
              icon: const Icon(
                Icons.refresh_rounded,
                color: UaqFixApp.primaryBlue,
                size: 22,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.session.esTecnico
                      ? const Color(0xFF0D9488).withValues(alpha: 0.12)
                      : UaqFixApp.lightBlueBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.session.esTecnico
                        ? const Color(0xFF0D9488)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.session.esTecnico
                          ? Icons.engineering_rounded
                          : Icons.school_rounded,
                      size: 14,
                      color: widget.session.esTecnico
                          ? const Color(0xFF0D9488)
                          : UaqFixApp.primaryBlue,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.session.esTecnico ? "Técnico" : "Alumno",
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: widget.session.esTecnico
                            ? const Color(0xFF0D9488)
                            : UaqFixApp.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final Size viewSize =
                Size(constraints.maxWidth, constraints.maxHeight);

            int pinesIzquierda = 0;
            int pinesDerecha = 0;
            final List<ReporteMap> puntosRadar = [];
            final List<ReporteMap> pinesParaRenderizar = [];

            for (final pin in _pinesActivos) {
              final String id = (pin['reporteId'] ?? '').toString();
              final coords =
                  pin['coordenadas_ar'] ?? {'x': 0.0, 'y': 0.0, 'z': -1.5};
              final double worldX = (coords['x'] as num).toDouble();
              final double worldY = (coords['y'] as num).toDouble();
              final double worldZ = (coords['z'] as num).toDouble();

              final proyeccion = _proyectarPinAPantalla(
                  id, worldX, worldY, worldZ, viewSize);
              final bool enPantalla = proyeccion['enPantalla'] as bool;
              final double deltaYaw = proyeccion['deltaYaw'] as double;
              final double distancia = proyeccion['distancia'] as double;
              final Offset posPantalla = proyeccion['offset'] as Offset;
              final Color color = _colorPorTipo(pin['tipo']);

              puntosRadar.add({
                "deltaYaw": deltaYaw,
                "distancia": distancia,
                "color": color,
              });

              if (!enPantalla) {
                if (deltaYaw < 0) {
                  pinesIzquierda++;
                } else {
                  pinesDerecha++;
                }
                continue;
              }

              pinesParaRenderizar.add({
                "pin": pin,
                "pos": posPantalla,
                "distancia": distancia,
                "color": color,
              });
            }

            pinesParaRenderizar.sort((a, b) =>
                (b['distancia'] as double).compareTo(a['distancia'] as double));

            final List<Widget> widgetsPinesEnPantalla =
                pinesParaRenderizar.map((item) {
              final ReporteMap pin = item['pin'] as ReporteMap;
              final Offset posPantalla = item['pos'] as Offset;
              final double distancia = item['distancia'] as double;
              final Color color = item['color'] as Color;
              final bool esMio = (pin['creado_por_correo'] ?? '')
                      .toString()
                      .toLowerCase() ==
                  widget.session.correo.toLowerCase();

              final double escala = _calcularEscalaPorDistancia(distancia);
              final double opacidad =
                  (1.15 - (distancia / 12.0)).clamp(0.75, 1.0);

              return Positioned(
                left: posPantalla.dx - 64,
                top: posPantalla.dy - 50,
                child: GestureDetector(
                  onTap: () => _mostrarDetallePin(pin, distancia),
                  child: Opacity(
                    opacity: opacidad,
                    child: Transform.scale(
                      scale: escala,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 128,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x26000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      "${esMio ? 'Mío · ' : ''}${pin['tipo']?.toString().split(' ').first ?? 'Pin'} · ${distancia.toStringAsFixed(1)}m",
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: UaqFixApp.textDark,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            AnimatedBuilder(
                              animation: _pinPulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: color, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(
                                            alpha: 0.25 +
                                                (_pinPulseController.value *
                                                    0.22)),
                                        blurRadius: 8 +
                                            (_pinPulseController.value * 6),
                                        spreadRadius: 1 +
                                            (_pinPulseController.value * 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _iconoPorTipo(pin['tipo']),
                                    color: color,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList();

            final vm.Vector3 fwd =
                _dispositivoAMundo(vm.Vector3(0.0, 0.0, -1.0));
            final int gradosBrj =
                ((math.atan2(fwd.x, -fwd.z) * 180 / math.pi) % 360 + 360)
                        .round() %
                    360;

            return Stack(
              children: [
                if (_camaraLista &&
                    _cameraController != null &&
                    _cameraController!.value.previewSize != null)
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _cameraController!.value.previewSize!.height,
                        height: _cameraController!.value.previewSize!.width,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF0F172A),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    _mostrarFormularioNuevoPin(details.localPosition, viewSize);
                  },
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.transparent,
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ...widgetsPinesEnPantalla,
                if (pinesIzquierda > 0)
                  Positioned(
                    left: 12,
                    top: viewSize.height * 0.44,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 8)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chevron_left_rounded,
                                color: UaqFixApp.primaryBlue, size: 20),
                            Text(
                              "$pinesIzquierda",
                              style: const TextStyle(
                                color: UaqFixApp.primaryBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (pinesDerecha > 0)
                  Positioned(
                    right: 12,
                    top: viewSize.height * 0.44,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 8)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "$pinesDerecha",
                              style: const TextStyle(
                                color: UaqFixApp.primaryBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: UaqFixApp.primaryBlue, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_puntoTemporalPantalla != null)
                  Positioned(
                    left: _puntoTemporalPantalla!.dx - 22,
                    top: _puntoTemporalPantalla!.dy - 22,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: UaqFixApp.primaryBlue.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                Positioned(
                  top: 14,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_cargandoPines)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: UaqFixApp.primaryBlue,
                                ),
                              )
                            else
                              const Icon(
                                Icons.place_rounded,
                                color: UaqFixApp.primaryBlue,
                                size: 17,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _cargandoPines
                                  ? "Sincronizando..."
                                  : "${_pinesActivos.length} Pines · $gradosBrj°",
                              style: const TextStyle(
                                color: UaqFixApp.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFDBEAFE), width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          painter: _Radar360Painter(puntos: puntosRadar),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.session.esTecnico
                                ? Icons.fact_check_outlined
                                : Icons.compass_calibration_rounded,
                            color: widget.session.esTecnico
                                ? const Color(0xFF0D9488)
                                : UaqFixApp.primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.session.esTecnico
                                  ? "Modo Mantenimiento: Toca un pin AR para registrar evidencia y resolverlo"
                                  : "Toca un objeto para anclar un pin AR o toca uno existente para ver su estado",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: UaqFixApp.textDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Radar360Painter extends CustomPainter {
  final List<ReporteMap> puntos;

  _Radar360Painter({required this.puntos});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 6;

    final Paint fovPaint = Paint()
      ..color = UaqFixApp.primaryBlue.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - 0.46,
      0.92,
      true,
      fovPaint,
    );

    final Paint ringPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius * 0.55, ringPaint);

    final Paint userPaint = Paint()
      ..color = UaqFixApp.primaryBlue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, userPaint);

    for (final p in puntos) {
      final double deltaYaw = p['deltaYaw'] as double;
      final double dist = (p['distancia'] as double).clamp(0.4, 6.0);
      final Color color = p['color'] as Color;

      final double rNorm = (dist / 6.0) * (radius - 3);
      final double angleCanvas = deltaYaw - (math.pi / 2);

      final Offset dotPos = Offset(
        center.dx + rNorm * math.cos(angleCanvas),
        center.dy + rNorm * math.sin(angleCanvas),
      );

      final Paint dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotPos, 3.8, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Radar360Painter oldDelegate) => true;
}