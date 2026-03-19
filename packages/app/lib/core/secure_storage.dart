import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A saved account identity (no token — fetched fresh on login).
class SavedAccount {
  final String did;
  final String role;
  final String? organisation;
  final String? name;
  final String? email;
  final String? photoUrl;
  final int avatarColor; // stored as ARGB int

  const SavedAccount({
    required this.did,
    required this.role,
    this.organisation,
    this.name,
    this.email,
    this.photoUrl,
    this.avatarColor = 0xFF1A73E8,
  });

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (organisation != null && organisation!.isNotEmpty) return organisation!;
    if (did.length <= 20) return did;
    return '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
  }

  String get initials {
    if (name != null && name!.isNotEmpty) {
      final parts = name!.trim().split(' ');
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return name![0].toUpperCase();
    }
    if (organisation != null && organisation!.isNotEmpty) {
      return organisation![0].toUpperCase();
    }
    return did.length > 2 ? did.substring(did.length - 2).toUpperCase() : '?';
  }

  Map<String, dynamic> toJson() => {
        'did': did,
        'role': role,
        if (organisation != null) 'organisation': organisation,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'avatarColor': avatarColor,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
        did: j['did'] as String,
        role: j['role'] as String,
        organisation: j['organisation'] as String?,
        name: j['name'] as String?,
        email: j['email'] as String?,
        photoUrl: j['photoUrl'] as String?,
        avatarColor: (j['avatarColor'] as int?) ?? 0xFF1A73E8,
      );
}

/// Persists auth credentials securely on-device.
/// Supports multiple accounts — each stored by DID.
class SecureStorageService {
  static const _keyAccounts = 'accounts_v2';
  static const _keyActiveToken = 'active_token';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ---------------------------------------------------------------------------
  // Account list
  // ---------------------------------------------------------------------------

  Future<List<SavedAccount>> loadAccounts() async {
    final raw = await _storage.read(key: _keyAccounts);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SavedAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAccount(SavedAccount account) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere((a) => a.did == account.did);
    if (idx >= 0) {
      accounts[idx] = account; // update existing
    } else {
      accounts.add(account);
    }
    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  Future<void> removeAccount(String did) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.did == did);
    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  // ---------------------------------------------------------------------------
  // Active session token (cleared on sign-out, refreshed on login)
  // ---------------------------------------------------------------------------

  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyActiveToken, value: token);
  }

  Future<String?> loadToken() async {
    return _storage.read(key: _keyActiveToken);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _keyActiveToken);
  }

  // ---------------------------------------------------------------------------
  // Legacy helpers (kept for compatibility)
  // ---------------------------------------------------------------------------

  Future<void> saveSession({
    required String did,
    required String token,
    required String role,
    String? organisation,
    String? name,
    String? email,
    String? photoUrl,
    int avatarColor = 0xFF1A73E8,
  }) async {
    await saveAccount(SavedAccount(
      did: did, role: role,
      organisation: organisation,
      name: name,
      email: email,
      photoUrl: photoUrl,
      avatarColor: avatarColor,
    ));
    await saveToken(token);
  }

  Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: _keyAccounts),
      _storage.delete(key: _keyActiveToken),
    ]);
  }

  /// Returns DID + role even if the token has been cleared (e.g. after sign-out).
  Future<({String did, String role})?> loadIdentity() async {
    // Returns the most recently added account as the "active" one
    final accounts = await loadAccounts();
    if (accounts.isEmpty) return null;
    final a = accounts.last;
    return (did: a.did, role: a.role);
  }
}
