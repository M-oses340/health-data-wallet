import 'package:dio/dio.dart';

/// Thin wrapper around Dio that points at the local API server.
/// Change [baseUrl] to your deployed API URL for production.
class ApiClient {
  static const String baseUrl = 'http://localhost:3000';

  final Dio _dio;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ));

  // -------------------------------------------------------------------------
  // Patient endpoints
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> getPayments(String did) async {
    final res = await _dio.get('/patient/$did/payments');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAuditTrail(String did) async {
    final res = await _dio.get('/patient/$did/audit-trail');
    return res.data as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Marketplace endpoints
  // -------------------------------------------------------------------------

  Future<List<dynamic>> searchDatasets({String? category, String? dataType}) async {
    final res = await _dio.get('/marketplace/datasets', queryParameters: {
      if (category != null) 'category': category,
      if (dataType != null) 'dataType': dataType,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> submitComputationRequest(
      Map<String, dynamic> payload) async {
    final res = await _dio.post('/marketplace/requests', data: payload);
    return res.data as Map<String, dynamic>;
  }
}
