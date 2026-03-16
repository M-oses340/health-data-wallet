import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
    context.go(_selected == UserRole.patient ? '/patient' : '/researcher');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.health_and_safety, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Health Data Wallet',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Role toggle
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
                  onSelectionChanged: (s) => setState(() => _selected = s.first),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _didController,
                  decoration: InputDecoration(
                    labelText: _selected == UserRole.patient
                        ? 'Patient DID (did:key:…)'
                        : 'Wallet address (0x…)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _enter, child: const Text('Enter')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
