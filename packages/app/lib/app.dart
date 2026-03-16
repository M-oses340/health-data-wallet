import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/pages/biometric_auth_page.dart';
import 'features/auth/pages/role_select_page.dart';
import 'features/patient/pages/patient_shell.dart';
import 'features/researcher/pages/researcher_shell.dart';

class HealthDataApp extends StatefulWidget {
  const HealthDataApp({super.key});

  @override
  State<HealthDataApp> createState() => _HealthDataAppState();
}

class _HealthDataAppState extends State<HealthDataApp> {
  bool _biometricPassed = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Data Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: !_biometricPassed
          ? BiometricAuthPage(
              onAuthenticated: () => setState(() => _biometricPassed = true),
            )
          : BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is AuthAuthenticated) {
                  return state.role == UserRole.patient
                      ? const PatientShell()
                      : const ResearcherShell();
                }
                return const RoleSelectPage();
              },
            ),
    );
  }
}
