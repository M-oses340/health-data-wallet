import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';

class RoleSelectPage extends StatefulWidget {
  const RoleSelectPage({super.key});

  @override
  State<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends State<RoleSelectPage> {
  final _didController = TextEditingController();
  UserRole _selected = UserRole.patient;

  @override
  void dispose() {
    _didController.dispose();
    super.dispose();
  }

  void _enter() {
    final did = _didController.text.trim();
    if (did.isEmpty) return;
    context.read<AuthBloc>().add(SelectRole(_selected, did));
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo area
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(Icons.health_and_safety,
                          size: 52, color: scheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Health Data Wallet',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Own your data. Earn from it.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    // Role card
                    Card(
                      elevation: 0,
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Select your role',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            SegmentedButton<UserRole>(
                              segments: const [
                                ButtonSegment(
                                    value: UserRole.patient,
                                    label: Text('Patient'),
                                    icon: Icon(Icons.person)),
                                ButtonSegment(
                                    value: UserRole.researcher,
                                    label: Text('Researcher'),
                                    icon: Icon(Icons.science)),
                              ],
                              selected: {_selected},
                              onSelectionChanged: (s) =>
                                  setState(() => _selected = s.first),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _didController,
                              decoration: InputDecoration(
                                labelText: _selected == UserRole.patient
                                    ? 'Patient DID (did:key:…)'
                                    : 'Wallet address (0x…)',
                                prefixIcon: Icon(
                                  _selected == UserRole.patient
                                      ? Icons.badge
                                      : Icons.account_balance_wallet,
                                ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: scheme.surface,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _enter,
                              icon: const Icon(Icons.login),
                              label: const Text('Enter'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'End-to-end encrypted · HIPAA compliant',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
