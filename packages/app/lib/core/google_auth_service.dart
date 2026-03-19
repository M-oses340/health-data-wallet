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
  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// Opens the Google account picker and returns the selected account.
  /// Returns null if the user cancels.
  Future<GoogleSignInResult?> signIn() async {
    try {
      // signOut first so the picker always shows — lets users switch accounts
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) return null;
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
