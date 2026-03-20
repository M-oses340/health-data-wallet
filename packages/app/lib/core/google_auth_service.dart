import 'package:google_sign_in/google_sign_in.dart';

/// Result from a Google sign-in attempt.
class GoogleSignInResult {
  final String email;
  final String displayName;
  final String? photoUrl;

  const GoogleSignInResult({
    required this.email,
    required this.displayName,
    this.photoUrl,
  });
}

class GoogleAuthService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// Opens the Google account picker and returns the selected account.
  /// Returns null if the user cancels.
  Future<GoogleSignInResult?> signIn() async {
    try {
      await _ensureInitialized();
      // signOut first so the picker always shows — lets users switch accounts
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      return GoogleSignInResult(
        email: account.email,
        displayName: account.displayName ?? account.email.split('@').first,
        photoUrl: account.photoUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
