import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'api_service.dart';
import 'main.dart';

class ArWorkspaceScreen extends StatefulWidget {
  final String ubicacionQr;
  final String nombreZona;

  const ArWorkspaceScreen({
    super.key,
    required this.ubicacionQr,
    this.nombreZona = "Espacio AR",
  });

  @override
  State<ArWorkspaceScreen> createState() => _ArWorkspaceScreenState();
}

class _ArWorkspaceScreenState extends State<ArWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _camaraLista = false;

  List<Map<String, dynamic>> _pinesActivos = [];
  bool _cargandoPines = true;
  bool _modoTecnico = false;

  // Subscripciones de Fusión de Sensores (Giroscopio + Acelerómetro a 50Hz)
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Orientación espacial 3D de la cámara en radianes
  // _camYaw: [-pi, pi] (0 = frente al QR, pi/-pi = pared de atrás 180°)
  // _camPitch: [-pi/2, pi/2] (0 = horizonte nivelado, + = mirando arriba, - = abajo)
  double _camYaw = 0.0;
  double _camPitch = 0.0;
  DateTime? _ultimoEventoGyro;

  // Vector de gravedad normalizado (Acelerómetro) para anclar la vertical real
  double _gravX = 0.0;
  double _gravY = 9.81;
  double _gravZ = 0.0;
  bool _pitchInicializado = false;

  // Campo de visión óptico real de cámara trasera en modo vertical (en radianes)
  static const double _fovHorizontalRad = 0.98; // ~56 grados horizontales
  static const double _fovVerticalRad = 1.32;   // ~75 grados verticales

  Offset? _puntoTemporalPantalla;
  late AnimationController _pinPulseController;

  @override
  void initState() {
    super.initState();
    _pinPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _inicializarCamara();
    _iniciarFusionDeSensores3D();
    _cargarPinesDesdeAWS();
  }

  Future<void> _inicializarCamara() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() => _camaraLista = true);
        }
      }
    } catch (e) {
      debugPrint("Aviso cámara: $e");
    }
  }

  // Normaliza cualquier ángulo al rango [-pi, pi] para permitir giros infinitos de 360°
  double _normalizarAngulo(double anguloRad) {
    double a = (anguloRad + math.pi) % (2 * math.pi);
    if (a < 0) a += 2 * math.pi;
    return a - math.pi;
  }

  // Fusión de Sensores 3D: Acelerómetro (Gravedad absoluta) + Giroscopio (Alta velocidad 50Hz)
  void _iniciarFusionDeSensores3D() {
    // 1. Acelerómetro: Mantiene el ángulo vertical (Pitch) clavado al horizonte real sin deriva
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((AccelerometerEvent event) {
      // Filtro paso-bajo suave para aislar la gravedad de sacudidas de la mano
      _gravX = _gravX * 0.85 + event.x * 0.15;
      _gravY = _gravY * 0.85 + event.y * 0.15;
      _gravZ = _gravZ * 0.85 + event.z * 0.15;

      final double normG = math.sqrt(
        _gravX * _gravX + _gravY * _gravY + _gravZ * _gravZ,
      );
      if (normG < 1.0) return;

      // En vertical: Y apunta arriba, Z apunta hacia el usuario.
      // Al inclinar la cámara hacia el techo, Z se vuelve positivo.
      final double pitchGravedad = math.atan2(
        _gravZ,
        math.sqrt(_gravX * _gravX + _gravY * _gravY),
      );

      if (!_pitchInicializado) {
        _camPitch = pitchGravedad;
        _pitchInicializado = true;
      } else {
        // Filtro complementario: corrige cualquier deriva vertical con la gravedad real
        _camPitch = _camPitch * 0.92 + pitchGravedad * 0.08;
      }
    });

    // 2. Giroscopio a 50Hz: Proyecta la rotación sobre el vector de gravedad real del salón
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((GyroscopeEvent event) {
      final ahora = DateTime.now();
      if (_ultimoEventoGyro != null) {
        final double dt =
            ahora.difference(_ultimoEventoGyro!).inMicroseconds / 1000000.0;

        if (dt > 0.0 && dt < 0.2) {
          final double normG = math.sqrt(
            _gravX * _gravX + _gravY * _gravY + _gravZ * _gravZ,
          );

          // Vector unitario "Arriba" del mundo real respecto a la postura actual del teléfono
          final double ux = normG > 1.0 ? (_gravX / normG) : 0.0;
          final double uy = normG > 1.0 ? (_gravY / normG) : 1.0;
          final double uz = normG > 1.0 ? (_gravZ / normG) : 0.0;

          // Zona muerta mínima solo para ruido electrónico en reposo
          final double wx = event.x.abs() > 0.008 ? event.x : 0.0;
          final double wy = event.y.abs() > 0.008 ? event.y : 0.0;
          final double wz = event.z.abs() > 0.008 ? event.z : 0.0;

          if (wx != 0.0 || wy != 0.0 || wz != 0.0) {
            // Producto punto: velocidad de giro horizontal real en el cuarto (independiente de la inclinación)
            final double yawRate = -(wx * ux + wy * uy + wz * uz);
            final double pitchRate = wx;

            setState(() {
              _camYaw = _normalizarAngulo(_camYaw + yawRate * dt);
              _camPitch = (_camPitch + pitchRate * dt)
                  .clamp(-math.pi / 2.1, math.pi / 2.1);
            });
          }
        }
      }
      _ultimoEventoGyro = ahora;
    });
  }

  void _recalibrarOrigenEspacial() {
    setState(() {
      _camYaw = 0.0;
    });
    _mostrarNotificacion(
      icono: Icons.center_focus_strong_rounded,
      texto: "Frente (0°) recalibrado hacia tu dirección actual",
      color: UaqFixApp.primaryBlue,
    );
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.3), width: 1),
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
    _pinPulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // Convierte el punto tocado en pantalla + distancia (m) en un vector 3D real {x, y, z} en el salón
  Map<String, double> _calcularVector3DMundo(
    Offset posicionToque,
    Size screenSize,
    double distanciaMetros,
  ) {
    // Desplazamiento angular del toque respecto al centro óptico de la cámara
    final double offsetYaw =
        ((posicionToque.dx / screenSize.width) - 0.5) * _fovHorizontalRad;
    final double offsetPitch =
        (0.5 - (posicionToque.dy / screenSize.height)) * _fovVerticalRad;

    final double pinYaw = _normalizarAngulo(_camYaw + offsetYaw);
    final double pinPitch =
        (_camPitch + offsetPitch).clamp(-math.pi / 2.1, math.pi / 2.1);

    // Proyección esférica a coordenadas cartesianas 3D (en metros)
    // Frente (0°) => Z negativo | Pared de atrás (180°) => Z positivo | Derecha (90°) => X positivo
    final double d = distanciaMetros.abs();
    final double worldX = d * math.cos(pinPitch) * math.sin(pinYaw);
    final double worldY = d * math.sin(pinPitch);
    final double worldZ = -d * math.cos(pinPitch) * math.cos(pinYaw);

    return {
      "x": double.parse(worldX.toStringAsFixed(2)),
      "y": double.parse(worldY.toStringAsFixed(2)),
      "z": double.parse(worldZ.toStringAsFixed(2)),
    };
  }

  // Convierte el vector 3D {x, y, z} guardado en DynamoDB a su posición exacta en pantalla
  Map<String, dynamic> _proyectarVector3DAPantalla(
    double x,
    double y,
    double z,
    Size screenSize,
  ) {
    final double distancia =
        math.sqrt(x * x + y * y + z * z).clamp(0.4, 20.0);

    // Ángulos esféricos absolutos del pin en el salón
    final double pinYaw = math.atan2(x, -z);
    final double pinPitch = math.asin((y / distancia).clamp(-1.0, 1.0));

    // Diferencia angular respecto a hacia dónde mira la cámara en este instante
    final double deltaYaw = _normalizarAngulo(pinYaw - _camYaw);
    final double deltaPitch = pinPitch - _camPitch;

    // Solo es visible si está frente a la cámara (hemisferio frontal) y dentro del FOV
    final bool enHemisferioFrontal = deltaYaw.abs() < (math.pi / 2.0);
    final double dx =
        (0.5 + (deltaYaw / _fovHorizontalRad)) * screenSize.width;
    final double dy =
        (0.5 - (deltaPitch / _fovVerticalRad)) * screenSize.height;

    final bool enPantalla = enHemisferioFrontal &&
        dx >= -45 &&
        dx <= screenSize.width + 45 &&
        dy >= -45 &&
        dy <= screenSize.height + 45;

    return {
      "offset": Offset(dx, dy),
      "enPantalla": enPantalla,
      "deltaYaw": deltaYaw,
      "distancia": distancia,
    };
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

  // Modal minimalista claro para crear un nuevo Pin AR
  void _mostrarFormularioNuevoPin(Offset toque, Size screenSize) {
    double distanciaMetros = 1.5;
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
            final coords3D =
                _calcularVector3DMundo(toque, screenSize, distanciaMetros);
            final double x = coords3D['x']!;
            final double y = coords3D['y']!;
            final double z = coords3D['z']!;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 14,
              ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                          const Text(
                            "Nuevo Reporte AR",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: UaqFixApp.textDark,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: UaqFixApp.lightBlueBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "X:$x  Y:$y  Z:$z",
                          style: const TextStyle(
                            color: UaqFixApp.primaryBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    value: tipoSeleccionado,
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

                  // Control de Distancia Radial al Objeto
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: UaqFixApp.backgroundSlate,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.straighten_rounded,
                          size: 18,
                          color: UaqFixApp.textMuted,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Distancia:",
                          style: TextStyle(
                            color: UaqFixApp.textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: distanciaMetros,
                            min: 0.5,
                            max: 5.0,
                            divisions: 9,
                            activeColor: UaqFixApp.primaryBlue,
                            inactiveColor: const Color(0xFFDBEAFE),
                            onChanged: (val) {
                              setModalState(() => distanciaMetros = val);
                            },
                          ),
                        ),
                        Text(
                          "${distanciaMetros.toStringAsFixed(1)} m",
                          style: const TextStyle(
                            color: UaqFixApp.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
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
                      hintText: "Ej. Nodo de red sin señal en mesa 2...",
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
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                _mostrarNotificacion(
                                  icono: Icons.check_circle_outline_rounded,
                                  texto:
                                      "Pin AR anclado en las coordenadas 3D del salón",
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

  // Modal minimalista claro para inspeccionar y resolver un Pin AR
  void _mostrarDetallePin(Map<String, dynamic> pin) {
    final coords = pin['coordenadas_ar'] ?? {'x': 0, 'y': 0, 'z': -1.5};
    final color = _colorPorTipo(pin['tipo']);
    bool resolviendo = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
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
                          color: color.withOpacity(0.12),
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
                              "Nodo: ${pin['ubicacion_qr']}",
                              style: const TextStyle(
                                color: UaqFixApp.textMuted,
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
                          color: color.withOpacity(0.12),
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
                  const SizedBox(height: 18),
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
                        const Text(
                          "Detalle del reporte",
                          style: TextStyle(
                            color: UaqFixApp.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pin['descripcion'] ?? 'Sin descripción',
                          style: const TextStyle(
                            color: UaqFixApp.textDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
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
                            Text(
                              "Vector 3D: X: ${coords['x']}m, Y: ${coords['y']}m, Z: ${coords['z']}m",
                              style: const TextStyle(
                                color: UaqFixApp.primaryBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_modoTecnico)
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
                        onPressed: resolviendo
                            ? null
                            : () async {
                                setModalState(() => resolviendo = true);
                                try {
                                  await ApiService.resolverReporte(
                                      pin['reporteId']);
                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  _mostrarNotificacion(
                                    icono: Icons.task_alt_rounded,
                                    texto: "Reporte marcado como resuelto",
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
                            : const Icon(Icons.check_circle_outline_rounded,
                                size: 18),
                        label: Text(
                          resolviendo
                              ? "Validando credencial..."
                              : "Marcar como Resuelto",
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: UaqFixApp.lightBlueBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            color: UaqFixApp.primaryBlue,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Activa el Modo Técnico en la barra superior para atender y cerrar esta incidencia.",
                              style: TextStyle(
                                color: UaqFixApp.primaryBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    int pinesIzquierda = 0;
    int pinesDerecha = 0;
    final List<Map<String, dynamic>> puntosRadar = [];

    // Pre-calculamos la proyección 3D de todos los pines activos
    final List<Widget> widgetsPinesEnPantalla = [];

    for (final pin in _pinesActivos) {
      final coords = pin['coordenadas_ar'] ?? {'x': 0.0, 'y': 0.0, 'z': -1.5};
      final double worldX = (coords['x'] as num).toDouble();
      final double worldY = (coords['y'] as num).toDouble();
      final double worldZ = (coords['z'] as num).toDouble();

      final proyeccion =
          _proyectarVector3DAPantalla(worldX, worldY, worldZ, screenSize);
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

      final double escala =
          (1.8 / distancia.clamp(0.8, 4.5)).clamp(0.75, 1.25);

      widgetsPinesEnPantalla.add(
        Positioned(
          left: posPantalla.dx - 55,
          top: posPantalla.dy - 45,
          child: GestureDetector(
            onTap: () => _mostrarDetallePin(pin),
            child: Transform.scale(
              scale: escala,
              child: SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
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
                              "${pin['tipo']?.toString().split(' ').first ?? 'Pin'} · ${distancia.toStringAsFixed(1)}m",
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
                            border: Border.all(color: color, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(
                                    0.25 + (_pinPulseController.value * 0.25)),
                                blurRadius:
                                    8 + (_pinPulseController.value * 8),
                                spreadRadius:
                                    1 + (_pinPulseController.value * 3),
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
    }

    final int gradosBrj = ((_camYaw * 180 / math.pi) % 360 + 360).round() % 360;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
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
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: _modoTecnico,
              showCheckmark: false,
              selectedColor: UaqFixApp.lightBlueBg,
              backgroundColor: UaqFixApp.backgroundSlate,
              side: BorderSide(
                color: _modoTecnico
                    ? UaqFixApp.primaryBlue
                    : const Color(0xFFE2E8F0),
              ),
              avatar: Icon(
                Icons.engineering_rounded,
                size: 16,
                color:
                    _modoTecnico ? UaqFixApp.primaryBlue : UaqFixApp.textMuted,
              ),
              label: Text(
                "Técnico",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _modoTecnico
                      ? UaqFixApp.primaryBlue
                      : UaqFixApp.textMuted,
                ),
              ),
              onSelected: (val) => setState(() => _modoTecnico = val),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Cámara en vivo
          if (_camaraLista && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              color: const Color(0xFF0F172A),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // 2. Superficie táctil para colocar nuevos pines
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              _mostrarFormularioNuevoPin(details.localPosition, screenSize);
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),

          // 3. Retícula central minimalista
          IgnorePointer(
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.55),
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

          // 4. Pines AR proyectados en 3D
          ...widgetsPinesEnPantalla,

          // 5. Indicadores laterales cuando hay pines detrás o a los lados
          if (pinesIzquierda > 0)
            Positioned(
              left: 12,
              top: screenSize.height * 0.42,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
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
              top: screenSize.height * 0.42,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
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

          // 6. Indicador de toque temporal
          if (_puntoTemporalPantalla != null)
            Positioned(
              left: _puntoTemporalPantalla!.dx - 22,
              top: _puntoTemporalPantalla!.dy - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: UaqFixApp.primaryBlue.withOpacity(0.2),
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

          // 7. HUD Superior: Contador de Pines + Radar Espacial 360°
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
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
                  ],
                ),

                // Mini-Radar 360° minimalista (muestra los pines delante, a los lados y atrás)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
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

          // 8. Guía inferior minimalista
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.threesixty_rounded,
                      color: UaqFixApp.primaryBlue,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        "Toca para anclar un pin 3D o gira 360° guiándote con el radar superior",
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
      ),
    );
  }
}

// Pintor del Radar Espacial 360° en la esquina superior derecha
class _Radar360Painter extends CustomPainter {
  final List<Map<String, dynamic>> puntos;

  _Radar360Painter({required this.puntos});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 6;

    // Cono de visión frontal de la cámara (hacia arriba en el radar)
    final Paint fovPaint = Paint()
      ..color = UaqFixApp.primaryBlue.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - 0.49,
      0.98,
      true,
      fovPaint,
    );

    // Anillo interior de referencia
    final Paint ringPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius * 0.55, ringPaint);

    // Punto central (Usuario)
    final Paint userPaint = Paint()
      ..color = UaqFixApp.primaryBlue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, userPaint);

    // Dibujar cada pin en su ángulo relativo (0° = arriba/frente, 180° = abajo/atrás)
    for (final p in puntos) {
      final double deltaYaw = p['deltaYaw'] as double;
      final double dist = (p['distancia'] as double).clamp(0.5, 5.0);
      final Color color = p['color'] as Color;

      final double rNorm = (dist / 5.0) * (radius - 3);
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