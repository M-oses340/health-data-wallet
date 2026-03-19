import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/api_client.dart';
import '../../../core/secure_storage.dart';
import '../bloc/auth_bloc.dart';

class RoleSelectPage extends StatefulWidget {
  const RoleSelectPage({super.key});

  @override
  State<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends State<RoleSelectPage> {
  final _orgController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  UserRole _selected = UserRole.patient;
  bool _showRegister = false;
  List<SavedAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await context.read<ApiClient>().storage.loadAccounts();
    if (mounted) setState(() { _accounts = accounts; _loading = false; });
  }

  @override
  void dispose() {
    _orgController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _loginAs(SavedAccount account) {
    context.read<AuthBloc>().add(LoginWithDID(
          account.did,
          account.role == 'researcher' ? UserRole.researcher : UserRole.patient,
        ));
  }

  void _register() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (_selected == UserRole.researcher) {
      context.read<AuthBloc>().add(RegisterResearcher(
            name: name,
            email: email,
            organisation: _orgController.text.trim().isEmpty
                ? null
                : _orgController.text.trim(),
          ));
    } else {
      context.read<AuthBloc>().add(RegisterPatient(name: name, email: email));
    }
  }

  Future<void> _removeAccount(SavedAccount account) async {
    await context.read<ApiClient>().storage.removeAccount(account.did);
    _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAccounts = _accounts.isNotEmpty;

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

                    if (_loading)
                      const CircularProgressIndicator()
                    else if (!_showRegister && hasAccounts)
                      _AccountPicker(
                        accounts: _accounts,
                        onLogin: _loginAs,
                        onRemove: _removeAccount,
                        onAddAccount: () =>
                            setState(() => _showRegister = true),
                      )
                    else
                      _RegisterCard(
                        formKey: _formKey,
                        selected: _selected,
                        orgController: _orgController,
                        nameController: _nameController,
                        emailController: _emailController,
                        onRoleChanged: (r) => setState(() => _selected = r),
                        onRegister: _register,
                        canCancel: hasAccounts,
                        onCancel: () => setState(() => _showRegister = false),
                      ),

                    // Error banner
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        if (state is AuthError) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _ErrorBanner(message: state.message),
                          );
                        }
                        return const SizedBox.shrink();
                      },
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
                            'End-to-end encrypted · Self-sovereign identity',
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

// ---------------------------------------------------------------------------
// Account picker — shown when saved accounts exist
// ---------------------------------------------------------------------------

class _AccountPicker extends StatelessWidget {
  final List<SavedAccount> accounts;
  final ValueChanged<SavedAccount> onLogin;
  final ValueChanged<SavedAccount> onRemove;
  final VoidCallback onAddAccount;

  const _AccountPicker({
    required this.accounts,
    required this.onLogin,
    required this.onRemove,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose account',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...accounts.map((a) => _AccountTile(
                  account: a,
                  onTap: () => onLogin(a),
                  onRemove: () => onRemove(a),
                )),
            const SizedBox(height: 8),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final loading = state is AuthLoading;
                return OutlinedButton.icon(
                  onPressed: loading ? null : onAddAccount,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Add another account'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final SavedAccount account;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _AccountTile({
    required this.account,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isResearcher = account.role == 'researcher';

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final loading = state is AuthLoading;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(account.avatarColor).withValues(alpha: 0.2),
                    ),
                    child: account.photoUrl != null
                        ? ClipOval(
                            child: Image.network(
                              account.photoUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(account.initials,
                                    style: TextStyle(
                                        color: Color(account.avatarColor),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              account.initials,
                              style: TextStyle(
                                color: Color(account.avatarColor),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.email ?? (isResearcher ? 'Researcher' : 'Patient'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: scheme.onSurfaceVariant,
                      tooltip: 'Remove account',
                      onPressed: () => _confirmRemove(context),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
            'This removes "${account.displayName}" from this device. Your data on the server is not deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); onRemove(); },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Register card
// ---------------------------------------------------------------------------

class _RegisterCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final UserRole selected;
  final TextEditingController orgController;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final ValueChanged<UserRole> onRoleChanged;
  final VoidCallback onRegister;
  final bool canCancel;
  final VoidCallback onCancel;

  const _RegisterCard({
    required this.formKey,
    required this.selected,
    required this.orgController,
    required this.nameController,
    required this.emailController,
    required this.onRoleChanged,
    required this.onRegister,
    required this.canCancel,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create account',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: scheme.surface,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: scheme.surface,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  final valid = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                  return valid ? null : 'Enter a valid email';
                },
              ),
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
                selected: {selected},
                onSelectionChanged: (s) => onRoleChanged(s.first),
              ),
              const SizedBox(height: 12),
              if (selected == UserRole.researcher)
                TextFormField(
                  controller: orgController,
                  decoration: InputDecoration(
                    labelText: 'Organisation (optional)',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: scheme.surface,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: scheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'A unique DID and encrypted wallet will be generated and saved securely on this device.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              // Google sign-in
              OutlinedButton.icon(
                onPressed: () => context.read<AuthBloc>().add(
                      GoogleSignInEvent(
                        role: selected,
                        organisation: orgController.text.trim().isEmpty
                            ? null
                            : orgController.text.trim(),
                      ),
                    ),
                icon: Image.asset(
                  'assets/google_logo.png',
                  width: 20,
                  height: 20,
                ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ]),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final loading = state is AuthLoading;
                  return FilledButton.icon(
                    onPressed: loading ? null : onRegister,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.person_add),
                    label: const Text('Create Account'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              ),
              if (canCancel) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Back to accounts'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
