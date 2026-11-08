import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'api_service.dart';

void main() {
  runApp(const UaqFixDashboardApp());
}

class UaqFixDashboardApp extends StatelessWidget {
  const UaqFixDashboardApp({super.key});

  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color secondaryBlue = Color(0xFF2563EB);
  static const Color softBlueBg = Color(0xFFEFF6FF);
  static const Color borderBlue = Color(0xFFDBEAFE);
  static const Color bgSlate = Color(0xFFF8FAFC);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderSlate = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAQ Fix · Dashboard Administrativo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: bgSlate,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: secondaryBlue,
          surface: cardWhite,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const AdminDashboardScreen(),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<ReporteMap> _todosReportes = [];
  bool _cargando = true;
  bool _autoRefresh = true;
  Timer? _timer;
  DateTime _ultimaActualizacion = DateTime.now();

  int _menuIndex = 0;
  String _filtroEstado = 'Todos';
  String _filtroZona = 'Todas';
  final String _filtroCategoria = 'Todas';
  String _busqueda = '';

  ReporteMap? _reporteSeleccionadoPlano;

  @override
  void initState() {
    super.initState();
    _sincronizarDatos();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_autoRefresh) {
        _sincronizarDatos(silencioso: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sincronizarDatos({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() => _cargando = true);
    }
    try {
      final datos = await DashboardApiService.obtenerTodosLosReportes();
      if (mounted) {
        setState(() {
          _todosReportes = datos;
          _cargando = false;
          _ultimaActualizacion = DateTime.now();
          if (_reporteSeleccionadoPlano != null) {
            final idSel = _reporteSeleccionadoPlano!['reporteId'];
            ReporteMap? encontrado;
            for (final item in _todosReportes) {
              if (item['reporteId'] == idSel) {
                encontrado = item;
                break;
              }
            }
            _reporteSeleccionadoPlano = encontrado;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  String _nombreAmigableZona(String? qr) {
    switch (qr) {
      case 'qr_stand_proyectate_1':
        return 'Stand Proyéctate 1 · Feria FIF';
      case 'qr_salon_3_piso_2':
        return 'Aula de Cómputo 3 · Piso 2';
      case 'qr_rack_redes_fif':
        return 'Site de Redes y Telecomunicaciones';
      case 'qr_celda_industrial_04':
        return 'Celda Robótica 04 · Industria 4.0';
      default:
        return qr ?? 'Zona General';
    }
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

  String _formatearFecha(String? iso) {
    if (iso == null || iso.isEmpty) return 'Hace un momento';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes/${dt.year} · $hora:$min';
    } catch (_) {
      return iso;
    }
  }

  List<ReporteMap> get _reportesFiltrados {
    return _todosReportes.where((r) {
      final estado = (r['estado'] ?? 'Pendiente').toString();
      final zona = (r['ubicacion_qr'] ?? '').toString();
      final tipo = (r['tipo'] ?? '').toString();
      final desc = (r['descripcion'] ?? '').toString().toLowerCase();
      final autor = (r['creado_por_correo'] ?? '').toString().toLowerCase();

      if (_filtroEstado != 'Todos' && estado != _filtroEstado) return false;
      if (_filtroZona != 'Todas' && zona != _filtroZona) return false;
      if (_filtroCategoria != 'Todas' && tipo != _filtroCategoria) return false;
      if (_busqueda.isNotEmpty &&
          !desc.contains(_busqueda.toLowerCase()) &&
          !zona.toLowerCase().contains(_busqueda.toLowerCase()) &&
          !autor.contains(_busqueda.toLowerCase()) &&
          !tipo.toLowerCase().contains(_busqueda.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  void _abrirDialogoResolverConEvidencia(ReporteMap reporte) {
    final id = reporte['reporteId']?.toString();
    if (id == null) return;

    final tecNombreCtrl =
        TextEditingController(text: "Ing. Carlos Méndez (Mantenimiento)");
    final tecCorreoCtrl =
        TextEditingController(text: "carlos.mendez@mantenimiento.uaq.mx");
    String accion = "Reemplazo o reparación de componente";
    final evidenciaCtrl = TextEditingController();
    bool enviando = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.fact_check_rounded,
                        color: Color(0xFF0D9488)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Finalizar Reporte y Enviar Evidencia al Alumno',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: UaqFixDashboardApp.bgSlate,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alumno solicitante: ${reporte['creado_por_nombre'] ?? 'Estudiante UAQ'} (${reporte['creado_por_correo'] ?? 'alumnos.uaq.mx'})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: UaqFixDashboardApp.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Incidencia: "${reporte['descripcion'] ?? ''}"',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: tecNombreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Responsable Técnico',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: tecCorreoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Correo @mantenimiento.uaq.mx',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: accion,
                      decoration: const InputDecoration(
                        labelText: 'Acción correctiva ejecutada',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Reemplazo o reparación de componente',
                          child: Text('Reemplazo o reparación de componente'),
                        ),
                        DropdownMenuItem(
                          value: 'Restablecimiento de nodo / red',
                          child: Text('Restablecimiento de nodo / red'),
                        ),
                        DropdownMenuItem(
                          value: 'Retiro y cambio de mobiliario dañado',
                          child: Text('Retiro y cambio de mobiliario dañado'),
                        ),
                        DropdownMenuItem(
                          value: 'Aislamiento y corrección eléctrica',
                          child: Text('Aislamiento y corrección eléctrica'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => accion = v!),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: evidenciaCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'Retroalimentación / Evidencia para el alumno (Obligatorio)',
                        hintText:
                            'Describe qué se reparó para que el estudiante reciba la confirmación en su Centro de Notificaciones...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onPressed: enviando
                      ? null
                      : () async {
                          if (evidenciaCtrl.text.trim().isEmpty) return;
                          setDialogState(() => enviando = true);
                          final ok = await DashboardApiService.resolverReporte(
                            reporteId: id,
                            resueltoPorNombre: tecNombreCtrl.text.trim(),
                            resueltoPorCorreo: tecCorreoCtrl.text.trim(),
                            accionRealizada: accion,
                            evidenciaResolucion: evidenciaCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (ok && mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF0D9488),
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                    'Reporte resuelto. Notificación enviada a ${reporte['creado_por_correo'] ?? 'alumno'}.'),
                              ),
                            );
                            _sincronizarDatos();
                          }
                        },
                  icon: const Icon(Icons.send_and_archive_rounded, size: 18),
                  label: Text(enviando
                      ? 'Sincronizando...'
                      : 'Confirmar y Notificar al Alumno'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirGeneradorQrStand() {
    String qrSeleccionado = 'qr_stand_proyectate_1';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final urlQrImg =
                'https://api.qrserver.com/v1/create-qr-code/?size=320x320&margin=12&data=$qrSeleccionado';

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: UaqFixDashboardApp.softBlueBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded,
                        color: UaqFixDashboardApp.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Código QR Oficial de Calibración Espacial',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: qrSeleccionado,
                      decoration: const InputDecoration(
                        labelText:
                            'Selecciona el espacio a proyectar / imprimir',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'qr_stand_proyectate_1',
                            child: Text('Stand Proyéctate 1 · Feria FIF')),
                        DropdownMenuItem(
                            value: 'qr_salon_3_piso_2',
                            child: Text('Aula de Cómputo 3 · Piso 2')),
                        DropdownMenuItem(
                            value: 'qr_rack_redes_fif',
                            child: Text('Site de Redes y Telecomunicaciones')),
                        DropdownMenuItem(
                            value: 'qr_celda_industrial_04',
                            child: Text('Celda Robótica 04 · Industria 4.0')),
                      ],
                      onChanged: (v) =>
                          setModalState(() => qrSeleccionado = v!),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: UaqFixDashboardApp.borderBlue, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x141D4ED8),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Image.network(
                            urlQrImg,
                            width: 240,
                            height: 240,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 240,
                              height: 240,
                              child: Center(
                                child: Icon(Icons.qr_code_2_rounded,
                                    size: 160,
                                    color: UaqFixDashboardApp.primaryBlue),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _nombreAmigableZona(qrSeleccionado),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: UaqFixDashboardApp.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ID Nodo: $qrSeleccionado',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: UaqFixDashboardApp.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Escanea este código directamente con la cámara de UAQ Fix en tu celular para anclar reportes en el Stand de Proyéctate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: UaqFixDashboardApp.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UaqFixDashboardApp.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirModalNuevoReporteWeb() {
    String zona = 'qr_stand_proyectate_1';
    String tipo = 'Redes / Cómputo';
    final descCtrl = TextEditingController();
    double x = 0.6, y = 0.2, z = -1.5;
    bool guardando = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: UaqFixDashboardApp.softBlueBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_location_alt_rounded,
                        color: UaqFixDashboardApp.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Registrar Orden de Mantenimiento AR',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: zona,
                      decoration: const InputDecoration(
                        labelText: 'Nodo / Ubicación QR',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'qr_stand_proyectate_1',
                            child: Text('Stand Proyéctate 1 · Feria FIF')),
                        DropdownMenuItem(
                            value: 'qr_salon_3_piso_2',
                            child: Text('Aula de Cómputo 3 · Piso 2')),
                        DropdownMenuItem(
                            value: 'qr_rack_redes_fif',
                            child: Text('Site de Redes y Telecomunicaciones')),
                        DropdownMenuItem(
                            value: 'qr_celda_industrial_04',
                            child: Text('Celda Robótica 04 · Industria 4.0')),
                      ],
                      onChanged: (v) => setDialogState(() => zona = v!),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Redes / Cómputo',
                            child: Text('Redes / Cómputo')),
                        DropdownMenuItem(
                            value: 'Eléctrico / Sensores IoT',
                            child: Text('Eléctrico / Sensores IoT')),
                        DropdownMenuItem(
                            value: 'Infraestructura / Mobiliario',
                            child: Text('Infraestructura / Mobiliario')),
                        DropdownMenuItem(
                            value: 'Riesgo Crítico (Industria 4.0)',
                            child: Text('Riesgo Crítico (Industria 4.0)')),
                      ],
                      onChanged: (v) => setDialogState(() => tipo = v!),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción de la orden o anomalía',
                        hintText: 'Ej. Revisión de nodo en Stand Proyéctate...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Coordenada 3D asignada: X: ${x.toStringAsFixed(1)}m, Y: ${y.toStringAsFixed(1)}m, Z: ${z.toStringAsFixed(1)}m',
                            style: const TextStyle(
                              fontSize: 12,
                              color: UaqFixDashboardApp.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final rnd = math.Random();
                            setDialogState(() {
                              x = (rnd.nextDouble() * 3.0) - 1.5;
                              y = (rnd.nextDouble() * 1.6) - 0.4;
                              z = -(rnd.nextDouble() * 3.0 + 0.8);
                            });
                          },
                          icon: const Icon(Icons.shuffle_rounded, size: 16),
                          label: const Text('Variar Posición'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UaqFixDashboardApp.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onPressed: guardando
                      ? null
                      : () async {
                          if (descCtrl.text.trim().isEmpty) return;
                          setDialogState(() => guardando = true);
                          final ok =
                              await DashboardApiService.crearReporteDesdeWeb(
                            tipo: tipo,
                            descripcion: descCtrl.text.trim(),
                            ubicacionQr: zona,
                            x: x,
                            y: y,
                            z: z,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) _sincronizarDatos();
                        },
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(guardando ? 'Sincronizando...' : 'Crear Pin AR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _todosReportes.length;
    final pendientes = _todosReportes
        .where((r) => (r['estado'] ?? 'Pendiente') == 'Pendiente')
        .length;
    final resueltos =
        _todosReportes.where((r) => r['estado'] == 'Resuelto').length;
    final criticos = _todosReportes
        .where((r) =>
            r['tipo'] == 'Riesgo Crítico (Industria 4.0)' &&
            (r['estado'] ?? 'Pendiente') == 'Pendiente')
        .length;
    final tasaResolucion =
        total > 0 ? ((resueltos / total) * 100).round() : 100;

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(pendientes),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildKpiRow(
                          total: total,
                          pendientes: pendientes,
                          resueltos: resueltos,
                          criticos: criticos,
                          tasaResolucion: tasaResolucion,
                        ),
                        const SizedBox(height: 24),
                        if (_menuIndex == 0) ...[
                          _buildSeccionMapaYAnalitica(),
                          const SizedBox(height: 24),
                          _buildSeccionTablaReportes(),
                        ] else if (_menuIndex == 1) ...[
                          _buildSeccionMapaYAnalitica(expandido: true),
                        ] else ...[
                          _buildSeccionTablaReportes(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(int pendientesCount) {
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: UaqFixDashboardApp.cardWhite,
        border: Border(
          right: BorderSide(color: UaqFixDashboardApp.borderSlate, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: UaqFixDashboardApp.primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: UaqFixDashboardApp.primaryBlue
                            .withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UAQ Fix',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: UaqFixDashboardApp.textDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Control Center · I4.0',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: UaqFixDashboardApp.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: UaqFixDashboardApp.borderSlate),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Text(
              'PLATAFORMA DE GESTIÓN',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: UaqFixDashboardApp.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _itemMenuSidebar(
            index: 0,
            icon: Icons.dashboard_outlined,
            titulo: 'Resumen General',
          ),
          _itemMenuSidebar(
            index: 1,
            icon: Icons.radar_rounded,
            titulo: 'Gemelo Espacial 3D',
          ),
          _itemMenuSidebar(
            index: 2,
            icon: Icons.assignment_outlined,
            titulo: 'Bitácora y Evidencias',
            badge: pendientesCount > 0 ? pendientesCount.toString() : null,
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Text(
              'FILTRO RÁPIDO POR NODO QR',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: UaqFixDashboardApp.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _itemZonaSidebar('Todas', 'Todos los Espacios', Icons.apps_rounded),
          _itemZonaSidebar('qr_stand_proyectate_1',
              'Stand Proyéctate 1 (Feria)', Icons.stars_rounded),
          _itemZonaSidebar('qr_salon_3_piso_2', 'Aula Cómputo 3 (FIF)',
              Icons.computer_rounded),
          _itemZonaSidebar(
              'qr_rack_redes_fif', 'Site de Redes / Rack', Icons.dns_rounded),
          _itemZonaSidebar('qr_celda_industrial_04', 'Celda Robótica 04',
              Icons.precision_manufacturing_rounded),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: UaqFixDashboardApp.softBlueBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: UaqFixDashboardApp.borderBlue),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'AWS DynamoDB Activo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: UaqFixDashboardApp.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Región: us-east-1 · Serverless',
                  style: TextStyle(
                    fontSize: 11,
                    color: UaqFixDashboardApp.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sincronización en vivo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: UaqFixDashboardApp.primaryBlue,
                      ),
                    ),
                    SizedBox(
                      height: 22,
                      child: Switch(
                        value: _autoRefresh,
                        activeThumbColor: UaqFixDashboardApp.primaryBlue,
                        onChanged: (v) => setState(() => _autoRefresh = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemMenuSidebar({
    required int index,
    required IconData icon,
    required String titulo,
    String? badge,
  }) {
    final activo = _menuIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: activo ? UaqFixDashboardApp.softBlueBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _menuIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: activo
                      ? UaqFixDashboardApp.primaryBlue
                      : UaqFixDashboardApp.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                      color: activo
                          ? UaqFixDashboardApp.primaryBlue
                          : UaqFixDashboardApp.textDark,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: UaqFixDashboardApp.primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemZonaSidebar(String qrId, String label, IconData icono) {
    final seleccionado = _filtroZona == qrId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _filtroZona = qrId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                icono,
                size: 16,
                color: seleccionado
                    ? UaqFixDashboardApp.primaryBlue
                    : UaqFixDashboardApp.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        seleccionado ? FontWeight.w700 : FontWeight.w500,
                    color: seleccionado
                        ? UaqFixDashboardApp.primaryBlue
                        : UaqFixDashboardApp.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final horaSync =
        '${_ultimaActualizacion.hour.toString().padLeft(2, '0')}:${_ultimaActualizacion.minute.toString().padLeft(2, '0')}:${_ultimaActualizacion.second.toString().padLeft(2, '0')}';

    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: UaqFixDashboardApp.cardWhite,
        border: Border(
          bottom: BorderSide(color: UaqFixDashboardApp.borderSlate, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Panel Administrativo de Mantenimiento Espacial AR',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: UaqFixDashboardApp.textDark,
                ),
              ),
              Text(
                'Facultad de Informática UAQ · Proyéctate 8va Edición · Última lectura: $horaSync',
                style: const TextStyle(
                  fontSize: 12,
                  color: UaqFixDashboardApp.textMuted,
                ),
              ),
            ],
          ),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: UaqFixDashboardApp.primaryBlue,
                  side: const BorderSide(color: UaqFixDashboardApp.borderBlue),
                  backgroundColor: UaqFixDashboardApp.softBlueBg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _abrirGeneradorQrStand,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text(
                  'QR Stand Proyéctate',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: UaqFixDashboardApp.textDark,
                  side: const BorderSide(color: UaqFixDashboardApp.borderSlate),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _sincronizarDatos(),
                icon: _cargando
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Sincronizar AWS',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: UaqFixDashboardApp.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _abrirModalNuevoReporteWeb,
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text(
                  'Nueva Orden AR',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow({
    required int total,
    required int pendientes,
    required int resueltos,
    required int criticos,
    required int tasaResolucion,
  }) {
    return Row(
      children: [
        Expanded(
          child: _tarjetaKpi(
            titulo: 'Incidencias Totales',
            valor: total.toString(),
            subtitulo: 'Pines 3D registrados en DynamoDB',
            icono: Icons.view_in_ar_rounded,
            color: UaqFixDashboardApp.primaryBlue,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _tarjetaKpi(
            titulo: 'Pendientes de Atención',
            valor: pendientes.toString(),
            subtitulo: 'Activos en visores AR de técnicos',
            icono: Icons.pending_actions_rounded,
            color: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _tarjetaKpi(
            titulo: 'Atendidos con Evidencia',
            valor: '$resueltos ($tasaResolucion%)',
            subtitulo: 'Notificados al alumno solicitante',
            icono: Icons.task_alt_rounded,
            color: const Color(0xFF0D9488),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _tarjetaKpi(
            titulo: 'Riesgo Crítico (I4.0)',
            valor: criticos.toString(),
            subtitulo: 'Prioridad inmediata en laboratorio',
            icono: Icons.warning_amber_rounded,
            color: const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaKpi({
    required String titulo,
    required String valor,
    required String subtitulo,
    required IconData icono,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: UaqFixDashboardApp.cardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: UaqFixDashboardApp.borderSlate),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icono, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: UaqFixDashboardApp.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: UaqFixDashboardApp.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    fontSize: 11,
                    color: UaqFixDashboardApp.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionMapaYAnalitica({bool expandido = false}) {
    final reportesMapa = _todosReportes.where((r) {
      if (_filtroZona != 'Todas' && r['ubicacion_qr'] != _filtroZona) {
        return false;
      }
      if (_filtroEstado != 'Todos' &&
          (r['estado'] ?? 'Pendiente') != _filtroEstado) {
        return false;
      }
      return true;
    }).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: UaqFixDashboardApp.cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: UaqFixDashboardApp.borderSlate),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: UaqFixDashboardApp.softBlueBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.radar_rounded,
                            color: UaqFixDashboardApp.primaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Gemelo Digital · Plano de Coordenadas Espaciales AR',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: UaqFixDashboardApp.textDark,
                              ),
                            ),
                            Text(
                              'Vista superior respecto al QR (0,0,0) · ${_filtroZona == 'Todas' ? 'Todos los nodos' : _nombreAmigableZona(_filtroZona)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: UaqFixDashboardApp.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: UaqFixDashboardApp.bgSlate,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: UaqFixDashboardApp.borderSlate),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filtroZona,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: UaqFixDashboardApp.textDark,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'Todas', child: Text('Todas las Zonas')),
                            DropdownMenuItem(
                                value: 'qr_stand_proyectate_1',
                                child: Text('Stand Proyéctate 1')),
                            DropdownMenuItem(
                                value: 'qr_salon_3_piso_2',
                                child: Text('Aula Cómputo 3')),
                            DropdownMenuItem(
                                value: 'qr_rack_redes_fif',
                                child: Text('Site de Redes')),
                            DropdownMenuItem(
                                value: 'qr_celda_industrial_04',
                                child: Text('Celda Robótica 04')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _filtroZona = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: expandido ? 420 : 295,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        final center = Offset(w / 2, h / 2);

                        return Stack(
                          children: [
                            CustomPaint(
                              size: Size(w, h),
                              painter: _PlanoArquitectonicoPainter(),
                            ),
                            Positioned(
                              left: center.dx - 48,
                              top: center.dy - 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: UaqFixDashboardApp.textDark,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.qr_code_2_rounded,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'QR (0,0,0)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ...reportesMapa.map((rep) {
                              final coords = rep['coordenadas_ar'] ??
                                  {'x': 0.0, 'y': 0.0, 'z': -1.5};
                              final double x =
                                  (coords['x'] as num?)?.toDouble() ?? 0.0;
                              final double y =
                                  (coords['y'] as num?)?.toDouble() ?? 0.0;
                              final double z =
                                  (coords['z'] as num?)?.toDouble() ?? -1.5;

                              final double px =
                                  (center.dx + (x / 5.0) * (w * 0.42))
                                      .clamp(24.0, w - 24.0);
                              final double py =
                                  (center.dy + (z / 5.0) * (h * 0.42))
                                      .clamp(24.0, h - 24.0);

                              final bool esResuelto =
                                  rep['estado'] == 'Resuelto';
                              final Color color = esResuelto
                                  ? const Color(0xFF0D9488)
                                  : _colorPorTipo(rep['tipo']);
                              final bool seleccionado =
                                  _reporteSeleccionadoPlano?['reporteId'] ==
                                      rep['reporteId'];

                              return Positioned(
                                left: px - 18,
                                top: py - 18,
                                child: Tooltip(
                                  message:
                                      '${rep['tipo']}\nReportó: ${rep['creado_por_correo'] ?? 'Alumno'}\n${rep['descripcion']}\n[X:$x, Y:$y, Z:$z]',
                                  child: InkWell(
                                    onTap: () => setState(() =>
                                        _reporteSeleccionadoPlano = rep),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: seleccionado ? 40 : 34,
                                      height: seleccionado ? 40 : 34,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: color,
                                          width: seleccionado ? 3.5 : 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                color.withValues(alpha: 0.35),
                                            blurRadius: seleccionado ? 12 : 6,
                                            spreadRadius: seleccionado ? 2 : 0,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        esResuelto
                                            ? Icons.check_rounded
                                            : _iconoPorTipo(rep['tipo']),
                                        size: 17,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            if (_reporteSeleccionadoPlano != null)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  width: 300,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: UaqFixDashboardApp.borderBlue),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x18000000),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _reporteSeleccionadoPlano![
                                                      'tipo'] ??
                                                  'Reporte',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.5,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => setState(() =>
                                                _reporteSeleccionadoPlano =
                                                    null),
                                            child: const Icon(Icons.close,
                                                size: 16),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _reporteSeleccionadoPlano![
                                                'descripcion'] ??
                                            '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: UaqFixDashboardApp.textDark,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Alumno: ${_reporteSeleccionadoPlano!['creado_por_correo'] ?? 'alumnos.uaq.mx'}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: UaqFixDashboardApp.primaryBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if ((_reporteSeleccionadoPlano![
                                                  'estado'] ??
                                              'Pendiente') ==
                                          'Pendiente') ...[
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 32,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF0D9488),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                            ),
                                            onPressed: () =>
                                                _abrirDialogoResolverConEvidencia(
                                                    _reporteSeleccionadoPlano!),
                                            icon: const Icon(
                                                Icons.fact_check_outlined,
                                                size: 14),
                                            label: const Text(
                                              'Resolver y Enviar Evidencia',
                                              style: TextStyle(fontSize: 11.5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: UaqFixDashboardApp.cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: UaqFixDashboardApp.borderSlate),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Distribución por Categoría',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: UaqFixDashboardApp.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Incidencias acumuladas por área técnica',
                  style: TextStyle(
                    fontSize: 12,
                    color: UaqFixDashboardApp.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                _barraCategoria('Redes / Cómputo', const Color(0xFF1D4ED8)),
                const SizedBox(height: 14),
                _barraCategoria(
                    'Eléctrico / Sensores IoT', const Color(0xFFD97706)),
                const SizedBox(height: 14),
                _barraCategoria(
                    'Infraestructura / Mobiliario', const Color(0xFF0D9488)),
                const SizedBox(height: 14),
                _barraCategoria(
                    'Riesgo Crítico (Industria 4.0)', const Color(0xFFDC2626)),
                const Divider(height: 28, color: UaqFixDashboardApp.borderSlate),
                const Text(
                  'Incidencias por Ubicación QR',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: UaqFixDashboardApp.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                _resumenZonaRow(
                    'qr_stand_proyectate_1', 'Stand Proyéctate 1 (Feria)'),
                const SizedBox(height: 8),
                _resumenZonaRow('qr_salon_3_piso_2', 'Aula de Cómputo 3 (FIF)'),
                const SizedBox(height: 8),
                _resumenZonaRow(
                    'qr_rack_redes_fif', 'Site de Redes / Telecom'),
                const SizedBox(height: 8),
                _resumenZonaRow(
                    'qr_celda_industrial_04', 'Celda Robótica 04 (I4.0)'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _barraCategoria(String categoria, Color color) {
    final total = _todosReportes.length;
    final count = _todosReportes.where((r) => r['tipo'] == categoria).length;
    final pct = total > 0 ? count / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              categoria,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: UaqFixDashboardApp.textDark,
              ),
            ),
            Text(
              '$count (${(pct * 100).round()}%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: UaqFixDashboardApp.bgSlate,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _resumenZonaRow(String qrId, String nombre) {
    final pendientesZona = _todosReportes
        .where((r) =>
            r['ubicacion_qr'] == qrId &&
            (r['estado'] ?? 'Pendiente') == 'Pendiente')
        .length;
    final totalZona =
        _todosReportes.where((r) => r['ubicacion_qr'] == qrId).length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          nombre,
          style: const TextStyle(
            fontSize: 12.5,
            color: UaqFixDashboardApp.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: pendientesZona > 0
                ? UaqFixDashboardApp.softBlueBg
                : UaqFixDashboardApp.bgSlate,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$pendientesZona activos / $totalZona total',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: pendientesZona > 0
                  ? UaqFixDashboardApp.primaryBlue
                  : UaqFixDashboardApp.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionTablaReportes() {
    final lista = _reportesFiltrados;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: UaqFixDashboardApp.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: UaqFixDashboardApp.borderSlate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bitácora de Incidencias, Autoría y Evidencia de Mantenimiento',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: UaqFixDashboardApp.textDark,
                    ),
                  ),
                  Text(
                    'Trazabilidad completa: Alumno solicitante (@alumnos.uaq.mx) y Técnico resolutor (@mantenimiento.uaq.mx)',
                    style: TextStyle(
                      fontSize: 12,
                      color: UaqFixDashboardApp.textMuted,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 240,
                    height: 40,
                    child: TextField(
                      onChanged: (val) => setState(() => _busqueda = val),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar por falla, correo o nodo...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        filled: true,
                        fillColor: UaqFixDashboardApp.bgSlate,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: UaqFixDashboardApp.borderSlate),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: UaqFixDashboardApp.borderSlate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _chipEstado('Todos'),
                  const SizedBox(width: 6),
                  _chipEstado('Pendiente'),
                  const SizedBox(width: 6),
                  _chipEstado('Resuelto'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_cargando && lista.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (lista.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: UaqFixDashboardApp.bgSlate,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 40, color: UaqFixDashboardApp.textMuted),
                  SizedBox(height: 10),
                  Text(
                    'No se encontraron reportes con los filtros seleccionados',
                    style: TextStyle(
                      color: UaqFixDashboardApp.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: lista.map((rep) => _filaReporteItem(rep)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _chipEstado(String estado) {
    final activo = _filtroEstado == estado;
    return ChoiceChip(
      label: Text(estado),
      selected: activo,
      showCheckmark: false,
      selectedColor: UaqFixDashboardApp.softBlueBg,
      backgroundColor: UaqFixDashboardApp.bgSlate,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: activo
            ? UaqFixDashboardApp.primaryBlue
            : UaqFixDashboardApp.textMuted,
      ),
      side: BorderSide(
        color: activo
            ? UaqFixDashboardApp.primaryBlue
            : UaqFixDashboardApp.borderSlate,
      ),
      onSelected: (_) => setState(() => _filtroEstado = estado),
    );
  }

  Widget _filaReporteItem(ReporteMap rep) {
    final String tipo = (rep['tipo'] ?? 'General').toString();
    final String desc = (rep['descripcion'] ?? 'Sin descripción').toString();
    final String qr = (rep['ubicacion_qr'] ?? '').toString();
    final String estado = (rep['estado'] ?? 'Pendiente').toString();
    final bool esPendiente = estado == 'Pendiente';
    final coords = rep['coordenadas_ar'] ?? {'x': 0, 'y': 0, 'z': 0};
    final Color color = _colorPorTipo(tipo);

    final String autorNombre =
        (rep['creado_por_nombre'] ?? 'Estudiante UAQ').toString();
    final String autorCorreo =
        (rep['creado_por_correo'] ?? 'alumnos.uaq.mx').toString();
    final String? evidencia = rep['evidencia_resolucion']?.toString();
    final String? tecNombre = rep['resuelto_por_nombre']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: esPendiente
            ? UaqFixDashboardApp.cardWhite
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esPendiente
              ? UaqFixDashboardApp.borderSlate
              : const Color(0xFFCCFBF1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconoPorTipo(tipo), color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tipo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatearFecha(rep['fecha']?.toString()),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: UaqFixDashboardApp.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: UaqFixDashboardApp.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Reportó: $autorNombre ($autorCorreo)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: UaqFixDashboardApp.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!esPendiente && evidencia != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Atendió ${tecNombre ?? "Mantenimiento"}: "$evidencia"',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF0F766E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(Icons.qr_code_rounded,
                    size: 16, color: UaqFixDashboardApp.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nombreAmigableZona(qr),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: UaqFixDashboardApp.textDark,
                        ),
                      ),
                      Text(
                        'ID: $qr',
                        style: const TextStyle(
                          fontSize: 11,
                          color: UaqFixDashboardApp.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: UaqFixDashboardApp.softBlueBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'X:${coords['x']}  Y:${coords['y']}  Z:${coords['z']}m',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: UaqFixDashboardApp.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 185,
            child: Align(
              alignment: Alignment.centerRight,
              child: esPendiente
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _abrirDialogoResolverConEvidencia(rep),
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text(
                        'Resolver + Evidencia',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF0D9488).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 15, color: Color(0xFF0D9488)),
                          SizedBox(width: 6),
                          Text(
                            'Evidencia Enviada',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0D9488),
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

class _PlanoArquitectonicoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    const double step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final center = Offset(size.width / 2, size.height / 2);

    final circlePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, size.height * 0.18, circlePaint);
    canvas.drawCircle(center, size.height * 0.34, circlePaint);

    final axisPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.2;
    canvas.drawLine(
        Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}