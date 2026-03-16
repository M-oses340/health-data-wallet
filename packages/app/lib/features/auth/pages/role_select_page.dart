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
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _didController.dispose();
    super.dispose();
  }

  void _enter() {
    final did = _didController.text.trim();
    if (_isRegisterMode) {
      // Register new patient — API generates the DID
      context.read<AuthBloc>().add(RegisterPatient());
      return;
    }
    if (did.isEmpty) return;
    context.read<AuthBloc>().add(LoginWithDID(did, _selected));
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
                    // Logo
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

                    // Auth card
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
                            // Register / Login toggle
                            Row(
                              children: [
                                Expanded(
                                  child: _ModeTab(
                                    label: 'Login',
                                    selected: !_isRegisterMode,
                                    onTap: () => setState(
                                        () => _isRegisterMode = false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ModeTab(
                                    label: 'Register',
                                    selected: _isRegisterMode,
                                    onTap: () => setState(
                                        () => _isRegisterMode = true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            if (!_isRegisterMode) ...[
                              // Role selector
                              Text('Select your role',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 16),
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
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: scheme.surface,
                                ),
                              ),
                            ] else ...[
                              // Register info
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: scheme.primary, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'A new DID and encrypted wallet will be generated for you automatically.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: scheme.onSurface),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Error state
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                if (state is AuthError) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline,
                                              color: Colors.red, size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(state.message,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                        color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),

                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                final loading = state is AuthLoading;
                                return FilledButton.icon(
                                  onPressed: loading ? null : _enter,
                                  icon: loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Icon(_isRegisterMode
                                          ? Icons.person_add
                                          : Icons.login),
                                  label: Text(_isRegisterMode
                                      ? 'Create Account'
                                      : 'Enter'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'End-to-end encrypted · HIPAA compliant',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
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

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}
