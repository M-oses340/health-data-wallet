import 'package:dio/dio.dart';
import 'env.dart';

/// Thin wrapper around Dio.
/// Set API_URL at build time: --dart-define=API_URL=https://your-api.com
class ApiClient {
  static String get baseUrl => Env.apiUrl;

  final Dio _dio;
  String? _authToken;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: Env.apiUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ));

  /// Set the JWT token after login — all subsequent requests will include it.
  void setAuthToken(String token) {
    _authToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearAuthToken() {
    _authToken = null;
    _dio.options.headers.remove('Authorization');
  }

  bool get isAuthenticated => _authToken != null;

  // -------------------------------------------------------------------------
  // Auth endpoints
  // -------------------------------------------------------------------------

  /// Register a new patient — returns { did, walletAddress, publicKey, token }
  Future<Map<String, dynamic>> registerPatient() async {
    final res = await _dio.post('/auth/register');
    return res.data as Map<String, dynamic>;
  }

  /// Login with DID — returns { token }
  Future<Map<String, dynamic>> login(String did, String role) async {
    final res = await _dio.post('/auth/login', data: {'did': did, 'role': role});
    return res.data as Map<String, dynamic>;
  }

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

  // -------------------------------------------------------------------------
  // Vault endpoints
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> uploadHealthData({
    required String patientDID,
    required String dataBase64,
    required String dataType,
    required String category,
  }) async {
    final res = await _dio.post('/vault/upload', data: {
      'patientDID': patientDID,
      'data': dataBase64,
      'dataType': dataType,
      'category': category,
    });
    return res.data as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Consent endpoints
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> revokeConsent({
    required String contractId,
    required String patientDID,
  }) async {
    final res = await _dio.post('/consent/revoke', data: {
      'contractId': contractId,
      'patientDID': patientDID,
    });
    return res.data as Map<String, dynamic>;
  }
}
