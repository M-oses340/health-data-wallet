import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores sensitive wallet credentials in the platform keychain/keystore.
/// Never use SharedPreferences for private keys.
class WalletStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyDid = 'wallet_did';
  static const _keyPrivateKey = 'wallet_private_key';
  static const _keyPublicKey = 'wallet_public_key';
  static const _keyAddress = 'wallet_address';
  static const _keyRole = 'wallet_role';
  static const _keyAuthToken = 'auth_token';

  static Future<void> saveWallet({
    required String did,
    required String privateKey,
    required String publicKey,
    required String address,
    required String role,
    required String token,
  }) async {
    await Future.wait([
      _storage.write(key: _keyDid, value: did),
      _storage.write(key: _keyPrivateKey, value: privateKey),
      _storage.write(key: _keyPublicKey, value: publicKey),
      _storage.write(key: _keyAddress, value: address),
      _storage.write(key: _keyRole, value: role),
      _storage.write(key: _keyAuthToken, value: token),
    ]);
  }

  static Future<void> saveAuthToken(String token) =>
      _storage.write(key: _keyAuthToken, value: token);

  static Future<String?> getDid() => _storage.read(key: _keyDid);
  static Future<String?> getPrivateKey() => _storage.read(key: _keyPrivateKey);
  static Future<String?> getPublicKey() => _storage.read(key: _keyPublicKey);
  static Future<String?> getAddress() => _storage.read(key: _keyAddress);
  static Future<String?> getRole() => _storage.read(key: _keyRole);
  static Future<String?> getAuthToken() => _storage.read(key: _keyAuthToken);

  static Future<bool> hasWallet() async =>
      (await _storage.read(key: _keyDid)) != null;

  static Future<void> clear() => _storage.deleteAll();
}
