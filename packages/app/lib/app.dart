import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/pages/role_select_page.dart';
import 'features/patient/pages/patient_shell.dart';
import 'features/researcher/pages/researcher_shell.dart';

class HealthDataApp extends StatelessWidget {
  const HealthDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Data Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          // navigation is handled by builder — nothing extra needed here
        },
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
