import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

  // Paleta de colores minimalista (Blancos y Azules)
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
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryBlue, width: 1.8),
          ),
          labelStyle: const TextStyle(color: textMuted, fontSize: 14),
        ),
      ),
      home: const HomeScannerScreen(),
    );
  }
}

class HomeScannerScreen extends StatefulWidget {
  const HomeScannerScreen({super.key});

  @override
  State<HomeScannerScreen> createState() => _HomeScannerScreenState();
}

class _HomeScannerScreenState extends State<HomeScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController();
  bool _navegando = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  void _abrirEspacioAR(String qrCode, String nombreZona) async {
    if (_navegando) return;
    setState(() => _navegando = true);
    await cameraController.stop();

    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArWorkspaceScreen(
          ubicacionQr: qrCode,
          nombreZona: nombreZona,
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

    await cameraController.start();
    if (mounted) {
      setState(() => _navegando = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: UaqFixApp.lightBlueBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  color: UaqFixApp.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "UAQ Fix",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: UaqFixApp.textDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    "Mantenimiento Espacial AR · FIF",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: UaqFixApp.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: Column(
        children: [
          // Sección Superior: Visor de Escáner QR con bordes redondeados
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: cameraController,
                      onDetect: (capture) {
                        for (final barcode in capture.barcodes) {
                          final String? code = barcode.rawValue;
                          if (code != null && code.isNotEmpty) {
                            _abrirEspacioAR(code, "Nodo QR Escaneado");
                            break;
                          }
                        }
                      },
                    ),

                    // Oscurecimiento sutil alrededor del marco
                    Container(color: Colors.black.withOpacity(0.18)),

                    // Marco de escaneo animado minimalista
                    Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.03);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 210,
                              height: 210,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.95),
                                  width: 2.2,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: UaqFixApp.primaryBlue
                                        .withOpacity(0.25),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: Colors.white70,
                                  size: 38,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Etiqueta flotante inferior dentro del visor
                    Positioned(
                      bottom: 16,
                      left: 24,
                      right: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.center_focus_strong_rounded,
                              size: 18,
                              color: UaqFixApp.primaryBlue,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Apunta al código QR del aula o equipo para calibrar",
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
                  ],
                ),
              ),
            ),
          ),

          // Sección Inferior: Selector de Espacios (Tarjetas limpias)
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                      const Text(
                        "Espacios de Prueba Directa",
                        style: TextStyle(
                          color: UaqFixApp.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Selecciona un entorno para visualizar o anclar reportes 3D:",
                    style: TextStyle(color: UaqFixApp.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _tarjetaZona(
                          icon: Icons.desktop_windows_rounded,
                          titulo: "Aula de Cómputo 3 · Piso 2",
                          subtitulo: "Facultad de Informática · Nodoqr_salon_3_piso_2",
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
                          subtitulo: "Laboratorio de Automatización · Nodo qr_celda_industrial_04",
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
  }) {
    return Material(
      color: UaqFixApp.backgroundSlate,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirEspacioAR(qrId, titulo),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: UaqFixApp.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Icon(icon, color: UaqFixApp.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: UaqFixApp.textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
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