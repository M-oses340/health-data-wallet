import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'env.dart';
import 'secure_storage.dart';

/// Thin wrapper around Dio.
/// Set API_URL at build time: --dart-define=API_URL=https://your-api.com
class ApiClient {
  static String get baseUrl => Env.apiUrl;

  final Dio _dio;
  final SecureStorageService storage = SecureStorageService();
  String? _authToken;
  bool _refreshing = false;
  /// Called when token refresh fails — wire up to AuthBloc.add(SignOut())
  VoidCallback? onSessionExpired;

  ApiClient() : _dio = Dio(BaseOptions(
      baseUrl: Env.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) async {
        // Auto-refresh on 401 Token expired (once)
        if (err.response?.statusCode == 401 &&
            err.response?.data?['error'] == 'Token expired' &&
            !_refreshing &&
            _authToken != null) {
          _refreshing = true;
          try {
            final res = await _dio.post('/auth/refresh');
            final newToken = res.data['token'] as String;
            setAuthToken(newToken);
            // Persist updated token
            await storage.saveToken(newToken);
            // Retry original request
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            final retried = await _dio.fetch(opts);
            return handler.resolve(retried);
          } catch (_) {
            // Refresh failed — clear token so the app redirects to login
            clearAuthToken();
            await storage.clearToken();
            onSessionExpired?.call();
          } finally {
            _refreshing = false;
          }
        }
        return handler.next(err);
      },
    ));
  }

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

  /// Register a new researcher — returns { did, walletAddress, publicKey, token }
  Future<Map<String, dynamic>> registerResearcher({String? organisation}) async {
    final res = await _dio.post('/auth/register/researcher',
        data: {if (organisation != null) 'organisation': organisation});
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
    final res = await _dio.get('/patient/payments', queryParameters: {'did': did});
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAuditTrail(String did) async {
    final res = await _dio.get('/patient/audit-trail', queryParameters: {'did': did});
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

  Future<Map<String, dynamic>> getVaultRecords(String did) async {
    final res = await _dio.get('/vault/records', queryParameters: {'did': did});
    return res.data as Map<String, dynamic>;
  }

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
