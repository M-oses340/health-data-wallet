import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/patient_bloc.dart';
import '../../../core/api_client.dart';
import 'payments_page.dart';
import 'audit_trail_page.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state as AuthAuthenticated;

    return BlocProvider(
      create: (ctx) =>
          PatientBloc(ctx.read<ApiClient>())..add(LoadPatientData(auth.did)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patient Wallet'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<PatientBloc>().add(LoadPatientData(auth.did)),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthBloc>().add(SignOut()),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [PaymentsPage(), AuditTrailPage()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.payments), label: 'Payments'),
            NavigationDestination(
                icon: Icon(Icons.history), label: 'Audit Trail'),
          ],
        ),
      ),
    );
  }
}
