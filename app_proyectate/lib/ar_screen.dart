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
  bool _cerrandoPantalla = false;

  List<Map<String, dynamic>> _pinesActivos = [];
  bool _cargandoPines = true;
  bool _modoTecnico = false;

  // Subscripciones de Sensores (Giroscopio + Acelerómetro)
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Matriz de Rotación 3D de Dispositivo a Mundo (R_WC)
  // Transforma cualquier vector de la cámara al salón: v_world = _rotWC * v_dev
  vm.Matrix3 _rotWC = vm.Matrix3.identity();
  vm.Matrix3 _rotRenderWC = vm.Matrix3.identity();
  bool _orientacionInicializada = false;
  DateTime? _ultimoEventoGyro;

  // Vector de gravedad medido en coordenadas del teléfono
  vm.Vector3 _gravDev = vm.Vector3(0.0, 9.81, 0.0);
  double _ultimoVelAngularMag = 0.0;

  // Posición 3D del usuario en el salón (en metros)
  vm.Vector3 _userPos = vm.Vector3.zero();

  // Detector de pasos estricto (solo cuando el usuario camina realmente, sin rotar el teléfono)
  bool _caminataAutoActiva = false;
  DateTime _ultimoPaso = DateTime.now();
  double _gravMagFiltrada = 9.81;

  // Apertura horizontal óptica de cámara trasera en modo retrato (~53 grados)
  static const double _tanHalfFovH = 0.498; // tan(26.5°)

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
    _iniciarMotorMatricial3D();
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

    try {
      final cam = _cameraController;
      _cameraController = null;
      await cam?.dispose();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // Construye una matriz 3D inicial alineada exactamente con la gravedad real del salón
  vm.Matrix3 _construirMatrizDesdeGravedad(vm.Vector3 upDev) {
    final vm.Vector3 yW = upDev.normalized();
    // Eje frontal de la cámara trasera es (0, 0, -1)
    vm.Vector3 forwardDev = vm.Vector3(0.0, 0.0, -1.0);
    if (yW.dot(forwardDev).abs() > 0.95) {
      forwardDev = vm.Vector3(0.0, 1.0, 0.0);
    }
    // Right = Forward x Up
    final vm.Vector3 xW = forwardDev.cross(yW).normalized();
    // Back (+Z_world) = Right x Up
    final vm.Vector3 zW = xW.cross(yW).normalized();

    // xW, yW, zW son las filas de R_WC
    return vm.Matrix3(
      xW.x, yW.x, zW.x,
      xW.y, yW.y, zW.y,
      xW.z, yW.z, zW.z,
    );
  }

  // Re-ortonormaliza la matriz 3x3 para evitar cualquier deformación numérica
  void _ortonormalizarMatriz(vm.Matrix3 m) {
    vm.Vector3 r0 = m.row0.normalized();
    vm.Vector3 r1 = m.row1;
    r1 = (r1 - r0 * r0.dot(r1)).normalized();
    vm.Vector3 r2 = r0.cross(r1).normalized();

    m.setRow(0, r0);
    m.setRow(1, r1);
    m.setRow(2, r2);
  }

  void _iniciarMotorMatricial3D() {
    // 1. Acelerómetro: Mide el vector "Arriba" (Gravedad) real en 3D
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((AccelerometerEvent event) {
      final vm.Vector3 lectura = vm.Vector3(event.x, event.y, event.z);
      final double mag = lectura.length;
      if (mag < 1.0) return;

      _gravDev = _gravDev * 0.88 + lectura * 0.12;

      if (!_orientacionInicializada && _gravDev.length > 5.0) {
        _rotWC = _construirMatrizDesdeGravedad(_gravDev);
        _rotRenderWC = _rotWC.clone();
        _orientacionInicializada = true;
      }

      // Podómetro opcional: solo cuenta pasos si el modo está activo y el teléfono NO está girando
      if (_caminataAutoActiva && _ultimoVelAngularMag < 0.22) {
        _gravMagFiltrada = _gravMagFiltrada * 0.7 + mag * 0.3;
        final double picoVertical = (_gravMagFiltrada - 9.81);
        final ahora = DateTime.now();
        if (picoVertical > 2.4 &&
            ahora.difference(_ultimoPaso).inMilliseconds > 550) {
          _ultimoPaso = ahora;
          _avanzarEnElSalon(0.45);
        }
      }
    });

    // 2. Giroscopio 3D + Filtro Complementario Mahony (Cero inversión de ejes y cero deriva)
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

      // Zona muerta suave para eliminar el pulso de la mano cuando sostienes el celular fijo
      const double deadzone = 0.022;
      final double gx = event.x.abs() > deadzone
          ? event.x - event.x.sign * deadzone
          : 0.0;
      final double gy = event.y.abs() > deadzone
          ? event.y - event.y.sign * deadzone
          : 0.0;
      final double gz = event.z.abs() > deadzone
          ? event.z - event.z.sign * deadzone
          : 0.0;

      vm.Vector3 omega = vm.Vector3(gx, gy, gz);
      _ultimoVelAngularMag = omega.length;

      // Corrección continua de Horizonte (Pitch y Roll) con el vector de Gravedad
      final double gravNorm = _gravDev.length;
      if ((gravNorm - 9.81).abs() < 1.5) {
        final vm.Vector3 uAccel = _gravDev / gravNorm;
        // La fila 1 de _rotWC es el vector "Arriba" estimado en coordenadas del teléfono
        final vm.Vector3 uEst = _rotWC.row1;
        // Producto cruz exacto que alinea el horizonte sin invertir ningún eje
        final vm.Vector3 errorTilt = uEst.cross(uAccel);
        omega += errorTilt * 1.85;
      }

      // Integración 3D exacta por fórmula de Rodrigues: R_new = R_old * exp([omega * dt]x)
      final double angle = omega.length * dt;
      if (angle > 0.0001) {
        final vm.Vector3 axis = omega.normalized();
        final double s = math.sin(angle);
        final double c = math.cos(angle);
        final double oc = 1.0 - c;

        final double x = axis.x, y = axis.y, z = axis.z;
        final vm.Matrix3 deltaR = vm.Matrix3(
          c + x * x * oc,     x * y * oc + z * s, x * z * oc - y * s,
          y * x * oc - z * s, c + y * y * oc,     y * z * oc + x * s,
          z * x * oc + y * s, z * y * oc - x * s, c + z * z * oc,
        );

        _rotWC = _rotWC * deltaR;
        _ortonormalizarMatriz(_rotWC);
      }

      // Suavizado exponencial de la matriz renderizada para eliminar cualquier vibración visual
      double diffSuma = 0.0;
      for (int i = 0; i < 9; i++) {
        diffSuma += (_rotWC.storage[i] - _rotRenderWC.storage[i]).abs();
      }

      if (diffSuma > 0.0015) {
        setState(() {
          for (int i = 0; i < 9; i++) {
            _rotRenderWC.storage[i] = _rotRenderWC.storage[i] * 0.65 +
                _rotWC.storage[i] * 0.35;
          }
          _ortonormalizarMatriz(_rotRenderWC);
        });
      }
    });
  }

  // Avanza o retrocede sobre el plano horizontal del salón en la dirección hacia donde miras
  void _avanzarEnElSalon(double metros) {
    // El eje frontal de la cámara en el mundo es _rotRenderWC * (0, 0, -1)
    final vm.Vector3 forwardWorld =
        _rotRenderWC.transform(vm.Vector3(0.0, 0.0, -1.0));
    final vm.Vector3 dirHorizontal =
        vm.Vector3(forwardWorld.x, 0.0, forwardWorld.z);
    if (dirHorizontal.length > 0.01) {
      dirHorizontal.normalize();
      setState(() {
        _userPos += dirHorizontal * metros;
        _userPos.x = _userPos.x.clamp(-20.0, 20.0);
        _userPos.z = _userPos.z.clamp(-20.0, 20.0);
      });
    }
  }

  void _recalibrarOrigenEspacial() {
    setState(() {
      if (_gravDev.length > 1.0) {
        _rotWC = _construirMatrizDesdeGravedad(_gravDev);
        _rotRenderWC = _rotWC.clone();
      } else {
        _rotWC = vm.Matrix3.identity();
        _rotRenderWC = vm.Matrix3.identity();
      }
      _userPos = vm.Vector3.zero();
    });
    _mostrarNotificacion(
      icono: Icons.center_focus_strong_rounded,
      texto: "Origen (0,0,0) recalibrado a tu vista actual",
      color: UaqFixApp.primaryBlue,
    );
  }

  // Convierte el toque en pantalla en un Rayo 3D unitario en el Mundo (se congela en el instante del toque)
  vm.Vector3 _calcularRayoMundoEnToque(Offset posicionToque, Size screenSize) {
    final double focalPx = (screenSize.width / 2.0) / _tanHalfFovH;
    final double xDev = (posicionToque.dx - screenSize.width / 2.0) / focalPx;
    final double yDev = (screenSize.height / 2.0 - posicionToque.dy) / focalPx;
    final vm.Vector3 rayDev = vm.Vector3(xDev, yDev, -1.0).normalized();

    // Transforma el rayo de la cámara a coordenadas fijas del salón
    return _rotRenderWC.transform(rayDev).normalized();
  }

  // Proyecta cualquier coordenada 3D {x, y, z} del salón a píxeles exactos en pantalla (Modelo Pinhole)
  Map<String, dynamic> _proyectarPunto3DAPantalla(
    double worldX,
    double worldY,
    double worldZ,
    Size screenSize,
  ) {
    final vm.Vector3 relWorld =
        vm.Vector3(worldX, worldY, worldZ) - _userPos;
    final double distancia = relWorld.length.clamp(0.3, 30.0);

    // Transformamos del salón a la cámara usando la transpuesta: v_dev = R_WC^T * relWorld
    final vm.Vector3 posCam = _rotRenderWC.transposed().transform(relWorld);

    final double focalPx = (screenSize.width / 2.0) / _tanHalfFovH;

    // La cámara trasera mira hacia -Z. El punto está frente a la cámara si posCam.z < -0.12
    final bool frenteACamara = posCam.z < -0.12;
    double dx = -9999.0;
    double dy = -9999.0;

    if (frenteACamara) {
      final double invZ = 1.0 / (-posCam.z);
      dx = (screenSize.width / 2.0) + (posCam.x * invZ) * focalPx;
      dy = (screenSize.height / 2.0) - (posCam.y * invZ) * focalPx;
    }

    final bool enPantalla = frenteACamara &&
        dx >= -65.0 &&
        dx <= screenSize.width + 65.0 &&
        dy >= -65.0 &&
        dy <= screenSize.height + 65.0;

    // Ángulo horizontal relativo para el radar 360° y flechas laterales
    final double deltaYaw = math.atan2(posCam.x, -posCam.z);

    return {
      "offset": Offset(dx, dy),
      "enPantalla": enPantalla,
      "deltaYaw": deltaYaw,
      "distancia": distancia,
    };
  }

  // Escala visual con perspectiva real: lejos (5m) = 0.38x, medio (1.8m) = 1.0x, cerca (0.6m) = 1.65x
  double _calcularEscalaPorDistancia(double distanciaMetros) {
    return (1.75 / distanciaMetros.clamp(0.45, 7.5)).clamp(0.38, 1.65);
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 95),
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

  // Modal minimalista claro: CONGELA el rayo 3D en el instante exacto del toque
  void _mostrarFormularioNuevoPin(Offset toque, Size screenSize) {
    // Congelamos la dirección 3D y posición en el milisegundo en que el usuario tocó la pantalla
    final vm.Vector3 rayoCongelado = _calcularRayoMundoEnToque(toque, screenSize);
    final vm.Vector3 origenCongelado = _userPos.clone();

    double distanciaMetros = 2.0;
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
            // Calculamos la coordenada usando el rayo CONGELADO (no importa si mueve el celular al escribir)
            final vm.Vector3 posFinal =
                origenCongelado + (rayoCongelado * distanciaMetros);
            final double x = double.parse(posFinal.x.toStringAsFixed(2));
            final double y = double.parse(posFinal.y.toStringAsFixed(2));
            final double z = double.parse(posFinal.z.toStringAsFixed(2));
            final double previewScale =
                _calcularEscalaPorDistancia(distanciaMetros);

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

                  // Control de Profundidad con indicador de tamaño por lejanía
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.straighten_rounded,
                                  size: 18,
                                  color: UaqFixApp.textMuted,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Profundidad en el salón:",
                                  style: TextStyle(
                                    color: UaqFixApp.textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              "${distanciaMetros.toStringAsFixed(1)} m (${distanciaMetros <= 1.2 ? 'Cerca' : distanciaMetros >= 3.5 ? 'Fondo' : 'Media'}) · Escala ${(previewScale * 100).round()}%",
                              style: const TextStyle(
                                color: UaqFixApp.primaryBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: distanciaMetros,
                          min: 0.6,
                          max: 6.0,
                          divisions: 18,
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
                      hintText: "Ej. Contacto dañado en la esquina del fondo...",
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
                                      "Pin AR fijado exactamente a ${distanciaMetros.toStringAsFixed(1)}m",
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

  void _mostrarDetallePin(Map<String, dynamic> pin, double distanciaActual) {
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
                              "Distancia actual: ${distanciaActual.toStringAsFixed(1)} metros",
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
                              "Coordenada fija: X: ${coords['x']}m, Y: ${coords['y']}m, Z: ${coords['z']}m",
                              style: const TextStyle(
                                color: UaqFixApp.textMuted,
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
              tooltip: "Recalibrar origen (0,0,0)",
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
                  color: _modoTecnico
                      ? UaqFixApp.primaryBlue
                      : UaqFixApp.textMuted,
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Usamos el tamaño exacto del área de cámara (sin restar el AppBar por error)
            final Size viewSize =
                Size(constraints.maxWidth, constraints.maxHeight);

            int pinesIzquierda = 0;
            int pinesDerecha = 0;
            final List<Map<String, dynamic>> puntosRadar = [];
            final List<Map<String, dynamic>> pinesParaRenderizar = [];

            for (final pin in _pinesActivos) {
              final coords =
                  pin['coordenadas_ar'] ?? {'x': 0.0, 'y': 0.0, 'z': -1.5};
              final double worldX = (coords['x'] as num).toDouble();
              final double worldY = (coords['y'] as num).toDouble();
              final double worldZ = (coords['z'] as num).toDouble();

              final proyeccion = _proyectarPunto3DAPantalla(
                  worldX, worldY, worldZ, viewSize);
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

            // Los pines más cercanos se dibujan encima de los más lejanos
            pinesParaRenderizar.sort((a, b) =>
                (b['distancia'] as double).compareTo(a['distancia'] as double));

            final List<Widget> widgetsPinesEnPantalla =
                pinesParaRenderizar.map((item) {
              final Map<String, dynamic> pin =
                  item['pin'] as Map<String, dynamic>;
              final Offset posPantalla = item['pos'] as Offset;
              final double distancia = item['distancia'] as double;
              final Color color = item['color'] as Color;

              final double escala = _calcularEscalaPorDistancia(distancia);
              final double opacidad =
                  (1.15 - (distancia / 12.0)).clamp(0.72, 1.0);

              return Positioned(
                left: posPantalla.dx - 60,
                top: posPantalla.dy - 50,
                child: GestureDetector(
                  onTap: () => _mostrarDetallePin(pin, distancia),
                  child: Opacity(
                    opacity: opacidad,
                    child: Transform.scale(
                      scale: escala,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 120,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
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
                                    border:
                                        Border.all(color: color, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withOpacity(0.25 +
                                            (_pinPulseController.value * 0.22)),
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

            // Rumbo horizontal actual en grados (0° = frente al origen)
            final vm.Vector3 fwd =
                _rotRenderWC.transform(vm.Vector3(0.0, 0.0, -1.0));
            final int gradosBrj =
                ((math.atan2(fwd.x, -fwd.z) * 180 / math.pi) % 360 + 360)
                        .round() %
                    360;

            return Stack(
              children: [
                // 1. Cámara en vivo con proporción óptica exacta (BoxFit.cover sin distorsión)
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

                // 2. Superficie táctil para colocar nuevos pines
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

                // 4. Pines AR anclados con matriz 3D y perspectiva de distancia
                ...widgetsPinesEnPantalla,

                // 5. Indicadores laterales cuando hay pines fuera de vista
                if (pinesIzquierda > 0)
                  Positioned(
                    left: 12,
                    top: viewSize.height * 0.44,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
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
                    top: viewSize.height * 0.44,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
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

                // 8. Control lateral de Acercamiento / Caminata en el Salón
                Positioned(
                  right: 16,
                  bottom: 92,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: "Acercarse (+0.5m)",
                          icon: const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: UaqFixApp.primaryBlue,
                          ),
                          onPressed: () => _avanzarEnElSalon(0.5),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() =>
                                _caminataAutoActiva = !_caminataAutoActiva);
                            _mostrarNotificacion(
                              icono: Icons.directions_walk_rounded,
                              texto: _caminataAutoActiva
                                  ? "Detector de pasos al caminar activado"
                                  : "Posición fija activada (máxima estabilidad)",
                              color: UaqFixApp.primaryBlue,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Icon(
                              Icons.directions_walk_rounded,
                              size: 18,
                              color: _caminataAutoActiva
                                  ? UaqFixApp.primaryBlue
                                  : UaqFixApp.textMuted,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: "Alejarse (-0.5m)",
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: UaqFixApp.primaryBlue,
                          ),
                          onPressed: () => _avanzarEnElSalon(-0.5),
                        ),
                      ],
                    ),
                  ),
                ),

                // 9. Guía inferior minimalista
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
                            Icons.view_in_ar_rounded,
                            color: UaqFixApp.primaryBlue,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              "Toca un punto para anclar un pin fijo 3D o usa las flechas para acercarte",
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
            );
          },
        ),
      ),
    );
  }
}

class _Radar360Painter extends CustomPainter {
  final List<Map<String, dynamic>> puntos;

  _Radar360Painter({required this.puntos});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 6;

    final Paint fovPaint = Paint()
      ..color = UaqFixApp.primaryBlue.withOpacity(0.15)
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