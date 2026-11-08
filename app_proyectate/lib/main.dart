import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api_service.dart';
import 'ar_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const UaqFixApp());
}

class UaqFixApp extends StatelessWidget {
  const UaqFixApp({super.key});

  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color lightBlueBg = Color(0xFFEFF6FF);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color backgroundSlate = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAQ Fix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundSlate,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentBlue,
          surface: surfaceWhite,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceWhite,
          foregroundColor: textDark,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: backgroundSlate,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlue, width: 1.8),
          ),
          labelStyle: const TextStyle(color: textMuted, fontSize: 13.5),
        ),
      ),
      home: const LiquidGlassLoginScreen(),
    );
  }
}

class LiquidGlassLoginScreen extends StatefulWidget {
  const LiquidGlassLoginScreen({super.key});

  @override
  State<LiquidGlassLoginScreen> createState() => _LiquidGlassLoginScreenState();
}

class _LiquidGlassLoginScreenState extends State<LiquidGlassLoginScreen>
    with SingleTickerProviderStateMixin {
  bool _esRegistro = false;
  bool _ocultarPassword = true;
  String? _mensajeError;

  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _correoCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  late AnimationController _bgAnimController;

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _extraerNombreDeCorreo(String correo) {
    final parteLocal = correo.split('@').first;
    final limpio = parteLocal.replaceAll('.', ' ').replaceAll('_', ' ');
    if (limpio.isEmpty) return "Usuario UAQ";
    return limpio
        .split(' ')
        .map((p) =>
            p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1)}' : '')
        .join(' ');
  }

  void _procesarAutenticacion() {
    setState(() => _mensajeError = null);

    final correo = _correoCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text.trim();
    final nombreInput = _nombreCtrl.text.trim();

    if (correo.isEmpty || pass.isEmpty || (_esRegistro && nombreInput.isEmpty)) {
      setState(() {
        _mensajeError = "Por favor completa todos los campos requeridos.";
      });
      return;
    }

    if (pass.length < 4) {
      setState(() {
        _mensajeError = "La contraseña debe tener al menos 4 caracteres.";
      });
      return;
    }

    final bool esAlumno = correo.endsWith('@alumnos.uaq.mx');
    final bool esMantenimiento = correo.endsWith('@mantenimiento.uaq.mx');

    if (!esAlumno && !esMantenimiento) {
      setState(() {
        _mensajeError =
            "Usa tu correo institucional @alumnos.uaq.mx (Estudiantes) o @mantenimiento.uaq.mx (Personal Técnico).";
      });
      return;
    }

    final nombreFinal =
        nombreInput.isNotEmpty ? nombreInput : _extraerNombreDeCorreo(correo);

    final session = UserSession(
      nombre: nombreFinal,
      correo: correo,
      esTecnico: esMantenimiento,
    );

    _entrarAHome(session);
  }

  void _entrarAHome(UserSession session) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, _) => HomeScannerScreen(session: session),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final correoActual = _correoCtrl.text.trim().toLowerCase();
    final bool detectaAlumno = correoActual.endsWith('@alumnos.uaq.mx');
    final bool detectaTecnico = correoActual.endsWith('@mantenimiento.uaq.mx');

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0ECFF),
                  Color(0xFFF8FAFC),
                  Color(0xFFDBEAFE),
                ],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (context, _) {
              final dy = (_bgAnimController.value - 0.5) * 35;
              return Stack(
                children: [
                  Positioned(
                    top: -60 + dy,
                    right: -50,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            UaqFixApp.primaryBlue.withValues(alpha: 0.28),
                            UaqFixApp.primaryBlue.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -80 - dy,
                    left: -60,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF0EA5E9).withValues(alpha: 0.22),
                            const Color(0xFF0EA5E9).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color:
                                UaqFixApp.primaryBlue.withValues(alpha: 0.32),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.view_in_ar_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "UAQ Fix",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: UaqFixApp.textDark,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Plataforma de Mantenimiento Espacial AR · FIF",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: UaqFixApp.textMuted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.76),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.95),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1E3A8A)
                                    .withValues(alpha: 0.08),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E8F0)
                                      .withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _esRegistro = false;
                                          _mensajeError = null;
                                        }),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: !_esRegistro
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(11),
                                            boxShadow: !_esRegistro
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                              alpha: 0.06),
                                                      blurRadius: 6,
                                                    )
                                                  ]
                                                : [],
                                          ),
                                          child: Text(
                                            "Iniciar Sesión",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: !_esRegistro
                                                  ? UaqFixApp.primaryBlue
                                                  : UaqFixApp.textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _esRegistro = true;
                                          _mensajeError = null;
                                        }),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _esRegistro
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(11),
                                            boxShadow: _esRegistro
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                              alpha: 0.06),
                                                      blurRadius: 6,
                                                    )
                                                  ]
                                                : [],
                                          ),
                                          child: Text(
                                            "Crear Cuenta UAQ",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _esRegistro
                                                  ? UaqFixApp.primaryBlue
                                                  : UaqFixApp.textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_esRegistro) ...[
                                TextField(
                                  controller: _nombreCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    labelText: "Nombre completo",
                                    hintText: "Ej. Diego Armando Millán",
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                      color: UaqFixApp.primaryBlue,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              TextField(
                                controller: _correoCtrl,
                                keyboardType: TextInputType.emailAddress,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: "Correo institucional UAQ",
                                  hintText:
                                      "usuario@alumnos.uaq.mx o @mantenimiento.uaq.mx",
                                  prefixIcon: Icon(
                                    Icons.alternate_email_rounded,
                                    color: UaqFixApp.primaryBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    detectaTecnico
                                        ? Icons.engineering_rounded
                                        : detectaAlumno
                                            ? Icons.school_rounded
                                            : Icons.info_outline_rounded,
                                    size: 15,
                                    color: detectaTecnico
                                        ? const Color(0xFF0D9488)
                                        : detectaAlumno
                                            ? UaqFixApp.primaryBlue
                                            : UaqFixApp.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      detectaTecnico
                                          ? "Rol detectado: Personal Técnico / Mantenimiento"
                                          : detectaAlumno
                                              ? "Rol detectado: Estudiante (@alumnos.uaq.mx)"
                                              : "Dominios válidos: @alumnos.uaq.mx y @mantenimiento.uaq.mx",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: detectaTecnico
                                            ? const Color(0xFF0D9488)
                                            : detectaAlumno
                                                ? UaqFixApp.primaryBlue
                                                : UaqFixApp.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _ocultarPassword,
                                decoration: InputDecoration(
                                  labelText: "Contraseña",
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: UaqFixApp.primaryBlue,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _ocultarPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: UaqFixApp.textMuted,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() =>
                                        _ocultarPassword = !_ocultarPassword),
                                  ),
                                ),
                              ),
                              if (_mensajeError != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFFECACA)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFDC2626),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _mensajeError!,
                                          style: const TextStyle(
                                            color: Color(0xFFDC2626),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: UaqFixApp.primaryBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  onPressed: _procesarAutenticacion,
                                  icon: Icon(
                                    _esRegistro
                                        ? Icons.person_add_alt_1_rounded
                                        : Icons.login_rounded,
                                    size: 19,
                                  ),
                                  label: Text(
                                    _esRegistro
                                        ? "Registrar Cuenta Institucional"
                                        : "Ingresar a UAQ Fix",
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Divider(color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  "ACCESO RÁPIDO PARA DEMOSTRACIÓN EN PROYÉCTATE",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: UaqFixApp.textMuted,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: UaqFixApp.primaryBlue,
                                        side: const BorderSide(
                                            color: Color(0xFFBFDBFE)),
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.65),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        _correoCtrl.text =
                                            "diego.millan@alumnos.uaq.mx";
                                        _passCtrl.text = "uaq2026";
                                        _nombreCtrl.text = "Diego Millán";
                                        _procesarAutenticacion();
                                      },
                                      icon: const Icon(Icons.school_rounded,
                                          size: 16),
                                      label: const Text(
                                        "Demo Alumno",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF0D9488),
                                        side: const BorderSide(
                                            color: Color(0xFF99F6E4)),
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.65),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        _correoCtrl.text =
                                            "soporte.fif@mantenimiento.uaq.mx";
                                        _passCtrl.text = "uaq2026";
                                        _nombreCtrl.text = "Ing. Mantenimiento";
                                        _procesarAutenticacion();
                                      },
                                      icon: const Icon(
                                          Icons.engineering_rounded,
                                          size: 16),
                                      label: const Text(
                                        "Demo Técnico",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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

class HomeScannerScreen extends StatefulWidget {
  final UserSession session;

  const HomeScannerScreen({super.key, required this.session});

  @override
  State<HomeScannerScreen> createState() => _HomeScannerScreenState();
}

class _HomeScannerScreenState extends State<HomeScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  MobileScannerController? _scannerController;
  bool _navegando = false;
  bool _escanerActivo = true;
  late AnimationController _pulseController;

  List<ReporteMap> _misReportes = [];
  bool _cargandoNotificaciones = false;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _inicializarEscaner();
    _cargarMisNotificaciones();

    _notifTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _cargarMisNotificaciones(silencioso: true);
    });
  }

  Future<void> _cargarMisNotificaciones({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() => _cargandoNotificaciones = true);
    }
    try {
      final lista =
          await ApiService.obtenerMisReportes(widget.session.correo);
      if (mounted) {
        setState(() {
          _misReportes = lista;
          _cargandoNotificaciones = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cargandoNotificaciones = false);
      }
    }
  }

  void _inicializarEscaner() {
    _scannerController?.dispose();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    if (mounted) {
      setState(() => _escanerActivo = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_navegando) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _scannerController?.stop();
    } else if (state == AppLifecycleState.resumed) {
      _inicializarEscaner();
    }
  }

  String _obtenerTituloAmigableQr(String qrCode) {
    switch (qrCode) {
      case 'qr_stand_proyectate_1':
        return 'Stand Proyéctate 1 · Feria FIF';
      case 'qr_salon_3_piso_2':
        return 'Aula de Cómputo 3 · Piso 2';
      case 'qr_rack_redes_fif':
        return 'Site de Redes y Telecomunicaciones';
      case 'qr_celda_industrial_04':
        return 'Celda Robótica 04 · Industria 4.0';
      default:
        return 'Nodo QR: $qrCode';
    }
  }

  Future<void> _abrirEspacioAR(String qrCode, String nombreZona) async {
    if (_navegando) return;
    setState(() {
      _navegando = true;
      _escanerActivo = false;
    });

    try {
      await _scannerController?.stop();
      await _scannerController?.dispose();
      _scannerController = null;
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArWorkspaceScreen(
          ubicacionQr: qrCode,
          nombreZona: nombreZona,
          session: widget.session,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      _inicializarEscaner();
      _cargarMisNotificaciones(silencioso: true);
      setState(() => _navegando = false);
    }
  }

  void _abrirCentroNotificaciones() {
    _cargarMisNotificaciones();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final resueltos =
            _misReportes.where((r) => r['estado'] == 'Resuelto').toList();
        final pendientes =
            _misReportes.where((r) => r['estado'] != 'Resuelto').toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      // Encabezado con Expanded para evitar overflow de 90px
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: UaqFixApp.lightBlueBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: UaqFixApp.primaryBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Centro de Notificaciones",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: UaqFixApp.textDark,
                                    ),
                                  ),
                                  Text(
                                    "Seguimiento y evidencia (${widget.session.correo})",
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
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Expanded(
                        child: _cargandoNotificaciones && _misReportes.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : _misReportes.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.mark_email_read_outlined,
                                            size: 48,
                                            color: UaqFixApp.textMuted
                                                .withValues(alpha: 0.5),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            "Aún no has generado reportes con tu cuenta",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: UaqFixApp.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            "Cuando ancles un pin AR y el equipo de mantenimiento lo repare, aquí recibirás quién lo atendió y qué hicieron para resolverlo.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: UaqFixApp.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      if (resueltos.isNotEmpty) ...[
                                        const Text(
                                          "ATENDIDOS CON EVIDENCIA DE MANTENIMIENTO",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0D9488),
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...resueltos.map((r) =>
                                            _tarjetaNotificacionReporte(r,
                                                esResuelto: true)),
                                        const SizedBox(height: 18),
                                      ],
                                      if (pendientes.isNotEmpty) ...[
                                        const Text(
                                          "REPORTES EN SEGUIMIENTO (PENDIENTES)",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: UaqFixApp.textMuted,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...pendientes.map((r) =>
                                            _tarjetaNotificacionReporte(r,
                                                esResuelto: false)),
                                      ],
                                    ],
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tarjetaNotificacionReporte(ReporteMap rep,
      {required bool esResuelto}) {
    final String tipo = (rep['tipo'] ?? 'Reporte').toString();
    final String desc = (rep['descripcion'] ?? '').toString();
    final String zona =
        _obtenerTituloAmigableQr((rep['ubicacion_qr'] ?? '').toString());
    final String tecNombre =
        (rep['resuelto_por_nombre'] ?? 'Personal de Mantenimiento').toString();
    final String tecCorreo =
        (rep['resuelto_por_correo'] ?? 'mantenimiento.uaq.mx').toString();
    final String accion =
        (rep['accion_realizada'] ?? 'Reparación completada').toString();
    final String evidencia = (rep['evidencia_resolucion'] ??
            'Se verificó y solucionó el desperfecto reportado.')
        .toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esResuelto ? const Color(0xFFF0FDFA) : UaqFixApp.backgroundSlate,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: esResuelto
              ? const Color(0xFF99F6E4)
              : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  tipo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: UaqFixApp.textDark,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: esResuelto
                      ? const Color(0xFF0D9488)
                      : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  esResuelto ? "Resuelto" : "En revisión",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Ubicación: $zona",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: UaqFixApp.primaryBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Tu reporte: \"$desc\"",
            style: const TextStyle(
              fontSize: 13,
              color: UaqFixApp.textDark,
            ),
          ),
          if (esResuelto) ...[
            const Divider(height: 20, color: Color(0xFFCCFBF1)),
            Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    size: 16, color: Color(0xFF0D9488)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Atendido por: $tecNombre ($tecCorreo)",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Acción realizada: $accion",
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: UaqFixApp.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Retroalimentación / Evidencia: $evidencia",
              style: const TextStyle(
                fontSize: 12.5,
                color: UaqFixApp.textDark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _cerrarSesion() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LiquidGlassLoginScreen()),
    );
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int notificacionesResueltas =
        _misReportes.where((r) => r['estado'] == 'Resuelto').length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.session.esTecnico
                      ? const Color(0xCCF0FDFA)
                      : UaqFixApp.lightBlueBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.session.esTecnico
                      ? Icons.engineering_rounded
                      : Icons.view_in_ar_rounded,
                  color: widget.session.esTecnico
                      ? const Color(0xFF0D9488)
                      : UaqFixApp.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "UAQ Fix",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                            color: UaqFixApp.textDark,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.session.esTecnico
                                ? const Color(0xFF0D9488)
                                    .withValues(alpha: 0.12)
                                : UaqFixApp.lightBlueBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.session.esTecnico ? "TÉCNICO" : "ALUMNO",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: widget.session.esTecnico
                                  ? const Color(0xFF0D9488)
                                  : UaqFixApp.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "${widget.session.nombre} · ${widget.session.correo}",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        color: UaqFixApp.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "Centro de Notificaciones y Mis Reportes",
                onPressed: _abrirCentroNotificaciones,
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: UaqFixApp.textDark,
                  size: 24,
                ),
              ),
              if (notificacionesResueltas > 0)
                Positioned(
                  right: 8,
                  top: 12,
                  child: GestureDetector(
                    onTap: _abrirCentroNotificaciones,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        notificacionesResueltas.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: "Cambiar cuenta / Cerrar sesión",
            onPressed: _cerrarSesion,
            icon: const Icon(
              Icons.logout_rounded,
              color: UaqFixApp.textMuted,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_escanerActivo && _scannerController != null)
                      MobileScanner(
                        controller: _scannerController!,
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final String? code = barcode.rawValue;
                            if (code != null && code.isNotEmpty) {
                              _abrirEspacioAR(
                                  code, _obtenerTituloAmigableQr(code));
                              break;
                            }
                          }
                        },
                      )
                    else
                      Container(
                        color: const Color(0xFF0F172A),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Activando visor espacial AR...",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Container(color: Colors.black.withValues(alpha: 0.18)),
                    Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.03);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 195,
                              height: 195,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  width: 2.2,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: UaqFixApp.primaryBlue
                                        .withValues(alpha: 0.25),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: Colors.white70,
                                  size: 36,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      left: 20,
                      right: 20,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.center_focus_strong_rounded,
                                  size: 17,
                                  color: UaqFixApp.primaryBlue,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "Escanea el QR del Stand Proyéctate o selecciona un nodo",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: UaqFixApp.textDark,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: UaqFixApp.surfaceWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fila con Expanded para eliminar el overflow de 81px
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: UaqFixApp.lightBlueBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: UaqFixApp.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "Nodos Espaciales AR",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: UaqFixApp.textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (!widget.session.esTecnico)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _abrirCentroNotificaciones,
                          icon: const Icon(Icons.history_edu_rounded, size: 15),
                          label: Text(
                            "Mis reportes (${_misReportes.length})",
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _tarjetaZona(
                          icon: Icons.stars_rounded,
                          titulo: "Stand Proyéctate 1 · Feria FIF",
                          subtitulo:
                              "Demostración en vivo 8va Edición · qr_stand_proyectate_1",
                          qrId: "qr_stand_proyectate_1",
                          destacado: true,
                        ),
                        const SizedBox(height: 10),
                        _tarjetaZona(
                          icon: Icons.desktop_windows_rounded,
                          titulo: "Aula de Cómputo 3 · Piso 2",
                          subtitulo:
                              "Facultad de Informática · Nodo qr_salon_3_piso_2",
                          qrId: "qr_salon_3_piso_2",
                        ),
                        const SizedBox(height: 10),
                        _tarjetaZona(
                          icon: Icons.dns_rounded,
                          titulo: "Site de Redes y Telecomunicaciones",
                          subtitulo: "Rack Principal · Nodo qr_rack_redes_fif",
                          qrId: "qr_rack_redes_fif",
                        ),
                        const SizedBox(height: 10),
                        _tarjetaZona(
                          icon: Icons.precision_manufacturing_rounded,
                          titulo: "Celda Robótica 04 · Industria 4.0",
                          subtitulo:
                              "Laboratorio de Automatización · Nodo qr_celda_industrial_04",
                          qrId: "qr_celda_industrial_04",
                        ),
                      ],
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

  Widget _tarjetaZona({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required String qrId,
    bool destacado = false,
  }) {
    return Material(
      color: destacado ? UaqFixApp.lightBlueBg : UaqFixApp.backgroundSlate,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirEspacioAR(qrId, titulo),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: destacado
                  ? UaqFixApp.primaryBlue.withValues(alpha: 0.45)
                  : const Color(0xFFE2E8F0),
              width: destacado ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: destacado
                      ? UaqFixApp.primaryBlue
                      : UaqFixApp.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Icon(
                  icon,
                  color: destacado ? Colors.white : UaqFixApp.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            titulo,
                            style: const TextStyle(
                              color: UaqFixApp.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (destacado) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: UaqFixApp.primaryBlue,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "EN VIVO",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: UaqFixApp.textMuted,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: UaqFixApp.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}