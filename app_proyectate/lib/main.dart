import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'ar_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UaqFixApp());
}

class UaqFixApp extends StatelessWidget {
  const UaqFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAQ-FIX AR 4.0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF10B981),
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

class _HomeScannerScreenState extends State<HomeScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  bool _navegando = false;

  void _abrirEspacioAR(String qrCode) async {
    if (_navegando) return;
    setState(() => _navegando = true);
    await cameraController.stop();

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArWorkspaceScreen(ubicacionQr: qrCode),
      ),
    );

    await cameraController.start();
    if (mounted) {
      setState(() => _navegando = false);
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.precision_manufacturing, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text(
              "UAQ-FIX | Industria 4.0 AR",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Visor de Escáner QR
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: cameraController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final String? code = barcode.rawValue;
                      if (code != null && code.isNotEmpty) {
                        _abrirEspacioAR(code);
                        break;
                      }
                    }
                  },
                ),
                // Marco guía de calibración QR
                Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xFF00E5FF), width: 2.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          "Escanea el QR del Aula o Maquinaria\npara calibrar el origen (0,0,0)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Panel inferior con Nodos de Prueba Rápida (Ideal para los jueces)
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Simulación Rápida (Sin QR físico):",
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Selecciona un nodo para cargar o anclar pines AR en AWS DynamoDB:",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _botonZonaDemo(
                        icon: Icons.computer,
                        label: "Salón 3 - Piso 2 (FIF)",
                        qrId: "qr_salon_3_piso_2",
                      ),
                      _botonZonaDemo(
                        icon: Icons.dns,
                        label: "Site de Redes / Rack",
                        qrId: "qr_rack_redes_fif",
                      ),
                      _botonZonaDemo(
                        icon: Icons.factory,
                        label: "Celda Robótica 04 (I4.0)",
                        qrId: "qr_celda_industrial_04",
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonZonaDemo({
    required IconData icon,
    required String label,
    required String qrId,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onPressed: () => _abrirEspacioAR(qrId),
      icon: Icon(icon, size: 18, color: const Color(0xFF00E5FF)),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}