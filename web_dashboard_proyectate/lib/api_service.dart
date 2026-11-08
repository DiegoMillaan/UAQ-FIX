import 'dart:convert';
import 'package:http/http.dart' as http;

typedef ReporteMap = Map<String, dynamic>;

class DashboardApiService {
  static const String baseUrl =
      "https://dbuyz09jy0.execute-api.us-east-1.amazonaws.com/dev";
  static const String adminToken = "super-secreto-uaq-2026";

  static const List<String> zonasConocidas = [
    "qr_stand_proyectate_1",
    "qr_salon_3_piso_2",
    "qr_rack_redes_fif",
    "qr_celda_industrial_04",
  ];

  /// Obtiene TODOS los reportes (Pendientes y Resueltos) de todas las zonas
  static Future<List<ReporteMap>> obtenerTodosLosReportes() async {
    final urlGlobal = Uri.parse('$baseUrl/reportes');

    try {
      final response = await http.get(
        urlGlobal,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final ReporteMap data = jsonDecode(response.body);
        final List<dynamic> lista = data['reportes'] ?? data['pines_ar'] ?? [];
        return lista.map((e) => ReporteMap.from(e)).toList();
      }
    } catch (_) {}

    final List<ReporteMap> acumulado = [];
    for (final qr in zonasConocidas) {
      try {
        final urlZona = Uri.parse('$baseUrl/ubicaciones/$qr/reportes');
        final res = await http.get(urlZona).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final ReporteMap data = jsonDecode(res.body);
          final List<dynamic> lista = data['pines_ar'] ?? [];
          acumulado.addAll(lista.map((e) => ReporteMap.from(e)));
        }
      } catch (_) {}
    }
    return acumulado;
  }

  /// Marca un reporte como Resuelto enviando la retroalimentación/evidencia al alumno
  static Future<bool> resolverReporte({
    required String reporteId,
    required String resueltoPorNombre,
    required String resueltoPorCorreo,
    required String accionRealizada,
    required String evidenciaResolucion,
  }) async {
    final url = Uri.parse('$baseUrl/reportes/$reporteId/resolver');
    final response = await http
        .put(
          url,
          headers: {
            "Content-Type": "application/json",
            "x-admin-token": adminToken,
          },
          body: jsonEncode({
            "resuelto_por_nombre": resueltoPorNombre,
            "resuelto_por_correo": resueltoPorCorreo,
            "accion_realizada": accionRealizada,
            "evidencia_resolucion": evidenciaResolucion,
          }),
        )
        .timeout(const Duration(seconds: 10));

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
    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "tipo": tipo,
            "descripcion": descripcion,
            "ubicacion_qr": ubicacionQr,
            "creado_por_nombre": "Centro de Control Web",
            "creado_por_correo": "admin@mantenimiento.uaq.mx",
            "coordenadas_ar": {
              "x": double.parse(x.toStringAsFixed(2)),
              "y": double.parse(y.toStringAsFixed(2)),
              "z": double.parse(z.toStringAsFixed(2)),
            }
          }),
        )
        .timeout(const Duration(seconds: 10));

    return response.statusCode == 201 || response.statusCode == 200;
  }
}