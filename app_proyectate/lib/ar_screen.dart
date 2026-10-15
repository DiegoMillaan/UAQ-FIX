import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'api_service.dart';

class ArWorkspaceScreen extends StatefulWidget {
  final String ubicacionQr;
  const ArWorkspaceScreen({super.key, required this.ubicacionQr});

  @override
  State<ArWorkspaceScreen> createState() => _ArWorkspaceScreenState();
}

class _ArWorkspaceScreenState extends State<ArWorkspaceScreen> {
  CameraController? _cameraController;
  bool _camaraLista = false;

  List<Map<String, dynamic>> _pinesActivos = [];
  bool _cargandoPines = true;
  bool _modoTecnico = false;

  // Coordenadas temporales mientras el usuario llena el formulario
  Offset? _puntoTemporalPantalla;

  @override
  void initState() {
    super.initState();
    _inicializarCamara();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al sincronizar pines: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // Convierte el toque en pantalla a coordenadas espaciales relativas {x, y} en metros (-2.0m a +2.0m)
  Map<String, double> _pantallaACoordenadasAR(Offset posicionToque, Size screenSize) {
    final double normX = ((posicionToque.dx / screenSize.width) - 0.5) * 4.0;
    final double normY = (0.5 - (posicionToque.dy / screenSize.height)) * 4.0;
    return {
      "x": double.parse(normX.toStringAsFixed(2)),
      "y": double.parse(normY.toStringAsFixed(2)),
    };
  }

  // Convierte las coordenadas {x, y} de DynamoDB de vuelta a la posición en el visor AR
  Offset _coordenadasARAPantalla(double x, double y, Size screenSize) {
    final double dx = ((x / 4.0) + 0.5) * screenSize.width;
    final double dy = (0.5 - (y / 4.0)) * screenSize.height;
    return Offset(
      dx.clamp(30.0, screenSize.width - 30.0),
      dy.clamp(80.0, screenSize.height - 100.0),
    );
  }

  // Semáforo de color según el tipo de falla
  Color _colorPorTipo(String? tipo) {
    switch (tipo) {
      case 'Riesgo Crítico (Industria 4.0)':
        return const Color(0xFFFF1744); // Rojo neón
      case 'Eléctrico / Sensores IoT':
        return const Color(0xFFFF9100); // Naranja alerta
      case 'Redes / Cómputo':
        return const Color(0xFF00E5FF); // Cian
      default:
        return const Color(0xFF10B981); // Verde esmeralda
    }
  }

  IconData _iconoPorTipo(String? tipo) {
    switch (tipo) {
      case 'Riesgo Crítico (Industria 4.0)':
        return Icons.warning_amber_rounded;
      case 'Eléctrico / Sensores IoT':
        return Icons.bolt;
      case 'Redes / Cómputo':
        return Icons.router;
      default:
        return Icons.build_circle_outlined;
    }
  }

  // 1. Al tocar el espacio vacío: fija el punto AR y abre el formulario
  void _mostrarFormularioNuevoPin(Offset toque, Size screenSize) {
    final coordsXY = _pantallaACoordenadasAR(toque, screenSize);
    final double x = coordsXY['x']!;
    final double y = coordsXY['y']!;
    double profundidadZ = -1.5; // 1.5 metros frente a la cámara por defecto

    String tipoSeleccionado = 'Eléctrico / Sensores IoT';
    final TextEditingController descController = TextEditingController();
    bool enviando = false;

    setState(() => _puntoTemporalPantalla = toque);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.add_location_alt, color: Color(0xFF00E5FF)),
                          SizedBox(width: 8),
                          Text(
                            "Anclar Reporte en AR",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E5FF)),
                        ),
                        child: Text(
                          "X:$x  Y:$y  Z:${profundidadZ.toStringAsFixed(1)}m",
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Categoría del problema
                  DropdownButtonFormField<String>(
                    value: tipoSeleccionado,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Clasificación de la Falla",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category, color: Color(0xFF00E5FF)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Eléctrico / Sensores IoT',
                        child: Text('Eléctrico / Sensores IoT'),
                      ),
                      DropdownMenuItem(
                        value: 'Redes / Cómputo',
                        child: Text('Redes / Cómputo'),
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
                  const SizedBox(height: 14),

                  // Control de Profundidad Z (Distancia al objeto)
                  Row(
                    children: [
                      const Text(
                        "Distancia al objeto (Eje Z):",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Expanded(
                        child: Slider(
                          value: profundidadZ.abs(),
                          min: 0.5,
                          max: 5.0,
                          divisions: 9,
                          activeColor: const Color(0xFF00E5FF),
                          label: "${profundidadZ.abs().toStringAsFixed(1)} m",
                          onChanged: (val) {
                            setModalState(() => profundidadZ = -val);
                          },
                        ),
                      ),
                      Text(
                        "${profundidadZ.abs().toStringAsFixed(1)}m",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  // Descripción detallada
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Descripción de la anomalía o falla",
                      hintText:
                          "Ej. Contacto sin corriente / Sobrecalentamiento en motor...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Botón de envío a AWS
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: enviando
                          ? null
                          : () async {
                              if (descController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        "Escribe una descripción para el reporte"),
                                  ),
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
                                  z: profundidadZ,
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        "✅ Pin AR anclado en AWS DynamoDB"),
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                                _cargarPinesDesdeAWS();
                              } catch (e) {
                                setModalState(() => enviando = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Error: $e"),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                      icon: enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        enviando
                            ? "Sincronizando con AWS..."
                            : "Fijar Pin AR en el Espacio",
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

  // 2. Al tocar un Pin AR existente: muestra los detalles y permite resolverlo en Modo Técnico
  void _mostrarDetallePin(Map<String, dynamic> pin) {
    final coords = pin['coordenadas_ar'] ?? {'x': 0, 'y': 0, 'z': -1.5};
    final color = _colorPorTipo(pin['tipo']);
    bool resolviendo = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(22.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withOpacity(0.2),
                        child: Icon(_iconoPorTipo(pin['tipo']), color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pin['tipo'] ?? 'Reporte General',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "ID: ${pin['reporteId']}",
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        backgroundColor: Colors.amber.withOpacity(0.2),
                        label: Text(
                          pin['estado'] ?? 'Pendiente',
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white24),
                  const Text(
                    "Diagnóstico / Descripción:",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pin['descripcion'] ?? 'Sin descripción',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Vector 3D: [X: ${coords['x']}, Y: ${coords['y']}, Z: ${coords['z']}m]",
                        style: const TextStyle(
                            color: Color(0xFF00E5FF), fontSize: 12),
                      ),
                      Text(
                        "Nodo: ${pin['ubicacion_qr']}",
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Si está en Modo Técnico, permite ejecutar el PUT con la llave maestra
                  if (_modoTecnico)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "🛠️ Reporte marcado como RESUELTO"),
                                      backgroundColor: Color(0xFF10B981),
                                    ),
                                  );
                                  _cargarPinesDesdeAWS();
                                } catch (e) {
                                  setModalState(() => resolviendo = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Error: $e"),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                        icon: resolviendo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.verified),
                        label: Text(
                          resolviendo
                              ? "Autorizando con Token..."
                              : "Marcar como Reparado (Token Admin)",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "💡 Activa el 'Modo Técnico' en la barra superior para resolver y retirar este pin AR.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 12),
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Visor Espacial AR",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(
              "QR: ${widget.ubicacionQr}",
              style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Recargar pines de AWS",
            onPressed: _cargarPinesDesdeAWS,
            icon: const Icon(Icons.sync, color: Color(0xFF00E5FF)),
          ),
          Row(
            children: [
              Text(
                "Técnico",
                style: TextStyle(
                  fontSize: 12,
                  color: _modoTecnico ? Colors.amber : Colors.white70,
                  fontWeight:
                      _modoTecnico ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Switch(
                value: _modoTecnico,
                activeColor: Colors.amber,
                onChanged: (val) => setState(() => _modoTecnico = val),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Fondo de Cámara en Tiempo Real
          if (_camaraLista && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              color: const Color(0xFF0F172A),
              child: const Center(
                child: Text(
                  "Iniciando visor óptico AR...",
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),

          // 2. Capa de Detección de Toques para Anclar Nuevos Pines
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

          // 3. Mira Central HUD (Referencia de Calibración (0,0,0))
          IgnorePointer(
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.add, color: Colors.white38, size: 20),
                ),
              ),
            ),
          ),

          // 4. Renderizado de los Pines AR Activos traídos de DynamoDB
          ..._pinesActivos.map((pin) {
            final coords = pin['coordenadas_ar'] ?? {'x': 0.0, 'y': 0.0, 'z': -1.5};
            final double x = (coords['x'] as num).toDouble();
            final double y = (coords['y'] as num).toDouble();
            final double z = (coords['z'] as num).toDouble();

            final posPantalla = _coordenadasARAPantalla(x, y, screenSize);
            final color = _colorPorTipo(pin['tipo']);

            // Escala visual según la distancia Z (más cerca = más grande)
            final double escala = (2.2 / z.abs().clamp(0.8, 4.0)).clamp(0.75, 1.35);

            return Positioned(
              left: posPantalla.dx - 32,
              top: posPantalla.dy - 32,
              child: GestureDetector(
                onTap: () => _mostrarDetallePin(pin),
                child: Transform.scale(
                  scale: escala,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color, width: 1.5),
                        ),
                        child: Text(
                          "${pin['tipo']?.toString().split(' ').first ?? 'Pin'} (${z.abs()}m)",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.6),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _iconoPorTipo(pin['tipo']),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // 5. Indicador de punto temporal mientras se llena el formulario
          if (_puntoTemporalPantalla != null)
            Positioned(
              left: _puntoTemporalPantalla!.dx - 24,
              top: _puntoTemporalPantalla!.dy - 24,
              child: const Icon(
                Icons.my_location,
                color: Color(0xFF00E5FF),
                size: 48,
              ),
            ),

          // 6. HUD Superior: Estado de conexión con AWS y Contador de Pines
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E5FF)),
                  ),
                  child: Row(
                    children: [
                      if (_cargandoPines)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00E5FF),
                          ),
                        )
                      else
                        const Icon(Icons.view_in_ar,
                            color: Color(0xFF00E5FF), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _cargandoPines
                            ? "Sincronizando AWS..."
                            : "Pines Activos: ${_pinesActivos.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_modoTecnico)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.admin_panel_settings,
                            color: Colors.black, size: 16),
                        SizedBox(width: 4),
                        Text(
                          "MODO MANTENIMIENTO",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 7. Instrucción flotante inferior
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  "👆 Toca cualquier punto sobre la cámara para fijar un Pin AR, o toca un pin existente para ver su diagnóstico.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}