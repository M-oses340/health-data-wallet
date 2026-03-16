import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  void dispose() {
    _categoryCtrl.dispose();
    _scopeCtrl.dispose();
    _durationCtrl.dispose();
    _dividendCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<ResearcherBloc>().add(SubmitRequest({
          'dataCategory': _categoryCtrl.text.trim(),
          'permittedScope': _scopeCtrl.text.trim(),
          'computationMethod': _method,
          'accessDuration': int.parse(_durationCtrl.text.trim()),
          'dataDividend': _dividendCtrl.text.trim(),
        }));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ResearcherBloc, ResearcherState>(
      listener: (context, state) {
        if (state is RequestSubmitted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Contract created: ${state.contractId}')),
          );
        }
        if (state is ResearcherError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${state.message}'), backgroundColor: Colors.red),
          );
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Computation Request',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              _field(_categoryCtrl, 'Data Category', 'e.g. cardiology'),
              const SizedBox(height: 16),
              _field(_scopeCtrl, 'Permitted Scope', 'e.g. cardiology-research'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                    labelText: 'Computation Method',
                    border: OutlineInputBorder()),
                items: ['FEDERATED_LEARNING', 'ZKP']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v!),
              ),
              const SizedBox(height: 16),
              _field(_durationCtrl, 'Access Duration (seconds)', '86400',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _field(_dividendCtrl, 'Dividend Offer (ETH)', '0.1',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              BlocBuilder<ResearcherBloc, ResearcherState>(
                builder: (context, state) => FilledButton(
                  onPressed: state is ResearcherLoading ? null : _submit,
                  child: state is ResearcherLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      );
}
