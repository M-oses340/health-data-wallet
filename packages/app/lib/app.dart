import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/pages/role_select_page.dart';
import 'features/patient/pages/patient_shell.dart';
import 'features/researcher/pages/researcher_shell.dart';

class HealthDataApp extends StatelessWidget {
  const HealthDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Health Data Wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      routerConfig: _router(context),
    );
  }

  GoRouter _router(BuildContext context) => GoRouter(
        initialLocation: '/',
        redirect: (ctx, state) {
          final auth = ctx.read<AuthBloc>().state;
          if (auth is AuthAuthenticated) {
            if (state.matchedLocation == '/') {
              return auth.role == UserRole.patient ? '/patient' : '/researcher';
            }
          }
          return null;
        },
        routes: [
          GoRoute(path: '/', builder: (_, __) => const RoleSelectPage()),
          GoRoute(path: '/patient', builder: (_, __) => const PatientShell()),
          GoRoute(path: '/researcher', builder: (_, __) => const ResearcherShell()),
        ],
      );
}
