import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/researcher_bloc.dart';

class SubmitRequestPage extends StatefulWidget {
  const SubmitRequestPage({super.key});

  @override
  State<SubmitRequestPage> createState() => _SubmitRequestPageState();
}

class _SubmitRequestPageState extends State<SubmitRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _categoryCtrl = TextEditingController();
  final _scopeCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '86400');
  final _dividendCtrl = TextEditingController(text: '0.1');
  String _method = 'FEDERATED_LEARNING';

  @override
  void initState() {
    super.initState();
    _dividendCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _scopeCtrl.dispose();
    _durationCtrl.dispose();
    _dividendCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // Convert ETH string to wei string (1 ETH = 1e18 wei)
    final ethVal = double.tryParse(_dividendCtrl.text.trim()) ?? 0.0;
    final weiVal = BigInt.from((ethVal * 1e18).round()).toString();
    final auth = context.read<AuthBloc>().state;
    final researcherDID = auth is AuthAuthenticated ? auth.did : '';
    context.read<ResearcherBloc>().add(SubmitRequest({
          'researcherDID': researcherDID,
          'dataCategory': _categoryCtrl.text.trim(),
          'permittedScope': _scopeCtrl.text.trim(),
          'computationMethod': _method,
          'accessDurationSeconds': int.parse(_durationCtrl.text.trim()),
          'dataDividendWei': weiVal,
        }));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividendPreview = _dividendCtrl.text.trim().isEmpty
        ? '0.0'
        : _dividendCtrl.text.trim();

    return BlocListener<ResearcherBloc, ResearcherState>(
      listener: (context, state) {
        if (state is RequestSubmitted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Contract created: ${state.contractId}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        if (state is ResearcherError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${state.message}'),
                backgroundColor: Colors.red),
          );
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dividend preview card
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.secondary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.onSecondary.withValues(alpha: 0.2),
                      ),
                      child: Icon(Icons.local_offer,
                          color: scheme.onSecondary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dividend Offer',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: scheme.onSecondary
                                        .withValues(alpha: 0.8))),
                        Text('$dividendPreview ETH',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    color: scheme.onSecondary,
                                    fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section: Data
              _sectionLabel(context, 'Data Details'),
              const SizedBox(height: 12),
              _field(_categoryCtrl, 'Data Category', 'e.g. cardiology',
                  icon: Icons.category_outlined),
              const SizedBox(height: 12),
              _field(_scopeCtrl, 'Permitted Scope', 'e.g. cardiology-research',
                  icon: Icons.policy_outlined),
              const SizedBox(height: 20),

              // Section: Computation
              _sectionLabel(context, 'Computation'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Method',
                  prefixIcon: const Icon(Icons.memory_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                ),
                items: ['FEDERATED_LEARNING', 'ZKP']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              const SizedBox(height: 20),

              // Section: Terms
              _sectionLabel(context, 'Terms'),
              const SizedBox(height: 12),
              _field(_durationCtrl, 'Access Duration (seconds)', '86400',
                  icon: Icons.timer_outlined,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(_dividendCtrl, 'Dividend Offer (ETH)', '0.1',
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 28),

              BlocBuilder<ResearcherBloc, ResearcherState>(
                builder: (context, state) => FilledButton.icon(
                  onPressed: state is ResearcherLoading ? null : _submit,
                  icon: state is ResearcherLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined),
                  label: const Text('Submit Request'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ));
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }
}
