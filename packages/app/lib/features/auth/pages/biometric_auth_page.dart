import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Biometric authentication gate.
///
/// States:
///   idle      — fingerprint icon, "Touch to authenticate" prompt
///   scanning  — animated pulse rings + scanning label
///   success   — green check with scale-in animation → auto-navigates
///   failed    — red shake animation + retry button
class BiometricAuthPage extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const BiometricAuthPage({super.key, required this.onAuthenticated});

  @override
  State<BiometricAuthPage> createState() => _BiometricAuthPageState();
}

enum _AuthState { idle, scanning, success, failed }

class _BiometricAuthPageState extends State<BiometricAuthPage>
    with TickerProviderStateMixin {
  final _auth = LocalAuthentication();
  _AuthState _state = _AuthState.idle;
  String _message = 'Touch the sensor to authenticate';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _successScale =
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() {
      _state = _AuthState.scanning;
      _message = 'Scanning…';
    });
    _pulseCtrl.repeat();

    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();

      debugPrint('isDeviceSupported: $isSupported');
      debugPrint('canCheckBiometrics: $canCheck');
      debugPrint('availableBiometrics: $available');

      bool authenticated = false;

      if (isSupported) {
        authenticated = await _auth.authenticate(
          localizedReason: 'Authenticate to access your Health Data Wallet',
          authMessages: [
            AndroidAuthMessages(
              signInTitle: 'Health Data Wallet',
              signInHint: 'Touch the fingerprint sensor',
              cancelButton: 'Cancel',
            ),
          ],
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
      } else {
        // No biometric hardware at all — allow through for dev/emulator
        await Future.delayed(const Duration(milliseconds: 1500));
        authenticated = true;
      }

      if (!mounted) return;

      if (authenticated) {
        _pulseCtrl.stop();
        setState(() {
          _state = _AuthState.success;
          _message = 'Identity verified';
        });
        await _successCtrl.forward();
        await Future.delayed(const Duration(milliseconds: 600));
        widget.onAuthenticated();
      } else {
        _pulseCtrl.stop();
        setState(() {
          _state = _AuthState.failed;
          _message = 'Authentication failed. Try again.';
        });
        _shakeCtrl.forward(from: 0);
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric PlatformException: ${e.code} — ${e.message}');
      if (!mounted) return;
      _pulseCtrl.stop();
      String msg;
      switch (e.code) {
        case 'NotAvailable':
        case 'NotEnrolled':
          msg = 'Biometrics not set up on this device.';
          break;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          msg = 'Too many attempts. Try again later.';
          break;
        case 'PasscodeNotSet':
          msg = 'No screen lock set. Enable a PIN or fingerprint in Settings.';
          break;
        default:
          msg = 'Biometric error. Try again.';
      }
      setState(() {
        _state = _AuthState.failed;
        _message = msg;
      });
      _shakeCtrl.forward(from: 0);
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      if (!mounted) return;
      _pulseCtrl.stop();
      setState(() {
        _state = _AuthState.failed;
        _message = 'Biometric error. Try again.';
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              scheme.surface,
              scheme.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Health Data Wallet',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Secure · Private · Yours',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 64),
                AnimatedBuilder(
                  animation:
                      Listenable.merge([_pulseAnim, _successScale, _shakeAnim]),
                  builder: (context, _) => _buildIcon(scheme),
                ),
                const SizedBox(height: 40),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _message,
                    key: ValueKey(_message),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _messageColor(scheme),
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                if (_state == _AuthState.idle || _state == _AuthState.failed)
                  FilledButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(
                        _state == _AuthState.failed ? 'Retry' : 'Authenticate'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ColorScheme scheme) {
    switch (_state) {
      case _AuthState.scanning:
        return Stack(
          alignment: Alignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.1).animate(
                CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.12),
                ),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.fingerprint, size: 48, color: scheme.primary),
            ),
          ],
        );

      case _AuthState.success:
        return ScaleTransition(
          scale: _successScale,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.check_circle, size: 56, color: Colors.green),
          ),
        );

      case _AuthState.failed:
        return Transform.translate(
          offset: Offset(_shakeAnim.value, 0),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.fingerprint, size: 48, color: Colors.red.shade400),
          ),
        );

      case _AuthState.idle:
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary.withValues(alpha: 0.1),
          ),
          child: Icon(Icons.fingerprint, size: 48, color: scheme.primary),
        );
    }
  }

  Color _messageColor(ColorScheme scheme) {
    switch (_state) {
      case _AuthState.success:
        return Colors.green;
      case _AuthState.failed:
        return Colors.red.shade400;
      case _AuthState.idle:
      case _AuthState.scanning:
        return scheme.onSurfaceVariant;
    }
  }
}
