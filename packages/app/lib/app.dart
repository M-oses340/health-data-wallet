import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/pages/biometric_auth_page.dart';
import 'features/auth/pages/role_select_page.dart';
import 'features/patient/pages/patient_shell.dart';
import 'features/researcher/pages/researcher_shell.dart';

const _kInactivityTimeout = Duration(minutes: 5);

class HealthDataApp extends StatefulWidget {
  const HealthDataApp({super.key});

  @override
  State<HealthDataApp> createState() => _HealthDataAppState();
}

class _HealthDataAppState extends State<HealthDataApp>
    with WidgetsBindingObserver {
  bool _biometricPassed = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final bg = _backgroundedAt;
      if (bg != null &&
          DateTime.now().difference(bg) >= _kInactivityTimeout &&
          _biometricPassed) {
        setState(() => _biometricPassed = false);
      }
      _backgroundedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Data Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: !_biometricPassed
          ? BiometricAuthPage(
              onAuthenticated: () => setState(() => _biometricPassed = true),
            )
          : BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                // Spinner only during the initial session restore
                if (state is AuthLoading) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (state is AuthAuthenticated) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                          parent: animation, curve: Curves.easeOut)),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: state.role == UserRole.patient
                        ? const PatientShell(key: ValueKey('patient'))
                        : const ResearcherShell(key: ValueKey('researcher')),
                  );
                }
                return const AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: RoleSelectPage(key: ValueKey('role')),
                );
              },
            ),
    );
  }
}
