import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/patient_bloc.dart';
import '../../../core/api_client.dart';
import 'payments_page.dart';
import 'audit_trail_page.dart';
import 'upload_data_page.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final auth = authState;
    final scheme = Theme.of(context).colorScheme;
    final shortDid = _shortId(auth.did);

    return BlocProvider(
      create: (ctx) =>
          PatientBloc(ctx.read<ApiClient>())..add(LoadPatientData(auth.did)),
      child: BlocBuilder<PatientBloc, PatientState>(
        builder: (context, state) {
          final newPayments = state is PatientLoaded ? state.payments.length : 0;

          return Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                SliverAppBar(
                  expandedHeight: 120,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [scheme.primary, scheme.tertiary],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.onPrimary.withValues(alpha: 0.2),
                                ),
                                child: Center(
                                  child: Text(
                                    _initials(auth.name),
                                    style: TextStyle(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      auth.name?.isNotEmpty == true
                                          ? auth.name!
                                          : 'Patient Wallet',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                color: scheme.onPrimary,
                                                fontWeight: FontWeight.bold)),
                                    GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(
                                            ClipboardData(text: auth.did));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content:
                                              Text('DID copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ));
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(shortDid,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: scheme.onPrimary
                                                          .withValues(
                                                              alpha: 0.8))),
                                          const SizedBox(width: 4),
                                          Icon(Icons.copy,
                                              size: 12,
                                              color: scheme.onPrimary
                                                  .withValues(alpha: 0.7)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.refresh,
                                    color: scheme.onPrimary),
                                onPressed: () => context
                                    .read<PatientBloc>()
                                    .add(LoadPatientData(auth.did)),
                              ),
                              IconButton(
                                icon: Icon(Icons.logout,
                                    color: scheme.onPrimary),
                                onPressed: () => context
                                    .read<AuthBloc>()
                                    .add(SignOut()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: IndexedStack(
                  key: ValueKey(_tab),
                  index: _tab,
                  children: const [PaymentsPage(), AuditTrailPage(), UploadDataPage()],
                ),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: newPayments > 0 && _tab != 0,
                    label: Text('$newPayments'),
                    child: const Icon(Icons.payments_outlined),
                  ),
                  selectedIcon: const Icon(Icons.payments),
                  label: 'Payments',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: 'Audit Trail',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.cloud_upload_outlined),
                  selectedIcon: Icon(Icons.cloud_upload),
                  label: 'Upload',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _shortId(String did) {
    if (did.length <= 20) return did;
    return '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return 'P';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }
}
