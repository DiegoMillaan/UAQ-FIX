import 'dart:convert';
import 'package:http/http.dart' as http;

class DashboardApiService {
  static const String baseUrl =
      "https://dbuyz09jy0.execute-api.us-east-1.amazonaws.com/dev";
  static const String adminToken = "super-secreto-uaq-2026";

  static const List<String> zonasConocidas = [
    "qr_salon_3_piso_2",
    "qr_rack_redes_fif",
    "qr_celda_industrial_04",
  ];

  /// Obtiene TODOS los reportes (Pendientes y Resueltos) de todas las zonas
  static Future<List<Map<String, dynamic>>> obtenerTodosLosReportes() async {
    final urlGlobal = Uri.parse('$baseUrl/reportes');

    try {
      final response = await http.get(
        urlGlobal,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> lista = data['reportes'] ?? data['pines_ar'] ?? [];
        return lista.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {
      // Si aún no se ha desplegado el endpoint global, consulta las zonas individualmente
    }

    // Respaldo automático consultando por zona
    final List<Map<String, dynamic>> acumulado = [];
    for (final qr in zonasConocidas) {
      try {
        final urlZona = Uri.parse('$baseUrl/ubicaciones/$qr/reportes');
        final res = await http.get(urlZona).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(res.body);
          final List<dynamic> lista = data['pines_ar'] ?? [];
          acumulado.addAll(lista.map((e) => Map<String, dynamic>.from(e)));
        }
      } catch (_) {}
    }
    return acumulado;
  }

  /// Marca un reporte como Resuelto enviando la llave maestra en cabeceras
  static Future<bool> resolverReporte(String reporteId) async {
    final url = Uri.parse('$baseUrl/reportes/$reporteId/resolver');
    final response = await http.put(
      url,
      headers: {
        "Content-Type": "application/json",
        "x-admin-token": adminToken,
      },
    ).timeout(const Duration(seconds: 10));

    return response.statusCode == 200;
  }

  /// Permite registrar un reporte desde el Dashboard para pruebas o mantenimiento preventivo
  static Future<bool> crearReporteDesdeWeb({
    required String tipo,
    required String descripcion,
    required String ubicacionQr,
    required double x,
    required double y,
    required double z,
  }) async {
    final url = Uri.parse('$baseUrl/reportes');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "tipo": tipo,
        "descripcion": descripcion,
        "ubicacion_qr": ubicacionQr,
        "coordenadas_ar": {
          "x": double.parse(x.toStringAsFixed(2)),
          "y": double.parse(y.toStringAsFixed(2)),
          "z": double.parse(z.toStringAsFixed(2)),
        }
      }),
    ).timeout(const Duration(seconds: 10));

    return response.statusCode == 201 || response.statusCode == 200;
  }
}