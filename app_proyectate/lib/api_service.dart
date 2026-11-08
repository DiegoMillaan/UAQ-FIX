import 'dart:convert';
import 'package:http/http.dart' as http;

typedef ReporteMap = Map<String, dynamic>;

class UserSession {
  final String nombre;
  final String correo;
  final bool esTecnico;

  const UserSession({
    required this.nombre,
    required this.correo,
    required this.esTecnico,
  });

  String get rolEtiqueta =>
      esTecnico ? "Mantenimiento UAQ" : "Comunidad Estudiantil";
}

class ApiService {
  static const String baseUrl =
      "https://dbuyz09jy0.execute-api.us-east-1.amazonaws.com/dev";

  static const String adminToken = "super-secreto-uaq-2026";

  /// 1. GET: Obtener todos los pines AR pendientes de un salón o zona QR
  static Future<List<ReporteMap>> obtenerPinesAR(String ubicacionQr) async {
    final encodedQr = Uri.encodeComponent(ubicacionQr);
    final url = Uri.parse('$baseUrl/ubicaciones/$encodedQr/reportes');

    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final ReporteMap data = jsonDecode(response.body);
        final List<dynamic> lista = data['pines_ar'] ?? [];
        return lista.map((item) => ReporteMap.from(item)).toList();
      } else {
        throw Exception(
            'Error del servidor (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Error al conectar con AWS para obtener pines: $e');
    }
  }

  /// 2. GET: Obtener los reportes de un alumno para su Centro de Notificaciones
  static Future<List<ReporteMap>> obtenerMisReportes(
      String correoAlumno) async {
    final url = Uri.parse('$baseUrl/reportes');
    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final ReporteMap data = jsonDecode(response.body);
        final List<dynamic> lista = data['reportes'] ?? [];
        final List<ReporteMap> todos =
            lista.map((item) => ReporteMap.from(item)).toList();

        final correoLimpio = correoAlumno.trim().toLowerCase();
        return todos.where((r) {
          final autor =
              (r['creado_por_correo'] ?? '').toString().trim().toLowerCase();
          return autor == correoLimpio;
        }).toList();
      } else {
        throw Exception('Error al consultar notificaciones');
      }
    } catch (e) {
      throw Exception('No se pudieron cargar las notificaciones: $e');
    }
  }

  /// 3. POST: Crear un nuevo reporte con coordenadas 3D {x, y, z} y datos del estudiante
  static Future<ReporteMap> crearReporte({
    required String tipo,
    required String descripcion,
    required String ubicacionQr,
    required double x,
    required double y,
    required double z,
    required String creadoPorNombre,
    required String creadoPorCorreo,
  }) async {
    final url = Uri.parse('$baseUrl/reportes');

    final payload = {
      "tipo": tipo,
      "descripcion": descripcion,
      "ubicacion_qr": ubicacionQr,
      "creado_por_nombre": creadoPorNombre,
      "creado_por_correo": creadoPorCorreo,
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
        return jsonDecode(response.body) as ReporteMap;
      } else {
        throw Exception(
            'Error al crear pin (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('No se pudo guardar el reporte en DynamoDB: $e');
    }
  }

  /// 4. PUT: Marcar reporte como Resuelto enviando retroalimentación/evidencia al alumno
  static Future<bool> resolverReporte({
    required String reporteId,
    required String resueltoPorNombre,
    required String resueltoPorCorreo,
    required String accionRealizada,
    required String evidenciaResolucion,
  }) async {
    final url = Uri.parse('$baseUrl/reportes/$reporteId/resolver');

    final payload = {
      "resuelto_por_nombre": resueltoPorNombre,
      "resuelto_por_correo": resueltoPorCorreo,
      "accion_realizada": accionRealizada,
      "evidencia_resolucion": evidenciaResolucion,
    };

    try {
      final response = await http
          .put(
            url,
            headers: {
              "Content-Type": "application/json",
              "x-admin-token": adminToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

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