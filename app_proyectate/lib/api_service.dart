import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // URL real generada por tu serverless deploy en us-east-1
  static const String baseUrl =
      "https://dbuyz09jy0.execute-api.us-east-1.amazonaws.com/dev";

  // Token definido en tu handler.js para personal de mantenimiento
  static const String adminToken = "super-secreto-uaq-2026";

  /// 1. GET: Obtener todos los pines AR pendientes de un salón o zona QR
  static Future<List<Map<String, dynamic>>> obtenerPinesAR(
      String ubicacionQr) async {
    final encodedQr = Uri.encodeComponent(ubicacionQr);
    final url = Uri.parse('$baseUrl/ubicaciones/$encodedQr/reportes');

    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> lista = data['pines_ar'] ?? [];
        return lista.map((item) => Map<String, dynamic>.from(item)).toList();
      } else {
        throw Exception(
            'Error del servidor (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Error al conectar con AWS para obtener pines: $e');
    }
  }

  /// 2. POST: Crear un nuevo reporte con coordenadas 3D {x, y, z}
  static Future<Map<String, dynamic>> crearReporte({
    required String tipo,
    required String descripcion,
    required String ubicacionQr,
    required double x,
    required double y,
    required double z,
  }) async {
    final url = Uri.parse('$baseUrl/reportes');

    final payload = {
      "tipo": tipo,
      "descripcion": descripcion,
      "ubicacion_qr": ubicacionQr,
      "coordenadas_ar": {
        "x": double.parse(x.toStringAsFixed(2)),
        "y": double.parse(y.toStringAsFixed(2)),
        "z": double.parse(z.toStringAsFixed(2)),
      }
    };

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Error al crear pin (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('No se pudo guardar el reporte en DynamoDB: $e');
    }
  }

  /// 3. PUT: Marcar reporte como Resuelto (Protegido con x-admin-token)
  static Future<bool> resolverReporte(String reporteId) async {
    final url = Uri.parse('$baseUrl/reportes/$reporteId/resolver');

    try {
      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "x-admin-token": adminToken,
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 403) {
        throw Exception('Acceso denegado: Token de administrador inválido.');
      } else {
        throw Exception(
            'Error al resolver reporte (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Fallo al intentar resolver el reporte: $e');
    }
  }
}