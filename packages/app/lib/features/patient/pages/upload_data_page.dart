import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/api_client.dart';

class UploadDataPage extends StatefulWidget {
  const UploadDataPage({super.key});

  @override
  State<UploadDataPage> createState() => _UploadDataPageState();
}

class _UploadDataPageState extends State<UploadDataPage> {
  final _formKey = GlobalKey<FormState>();
  final _heartRateCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  String _category = 'vitals';
  bool _loading = false;
  String? _successCid;
  String? _error;

  @override
  void dispose() {
    _heartRateCtrl.dispose();
    _spo2Ctrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _successCid = null; });

    final auth = context.read<AuthBloc>().state as AuthAuthenticated;
    final payload = <String, dynamic>{};
    if (_heartRateCtrl.text.isNotEmpty) {
      payload['heartRate'] = double.parse(_heartRateCtrl.text.trim());
    }
    if (_spo2Ctrl.text.isNotEmpty) {
      payload['spo2'] = double.parse(_spo2Ctrl.text.trim());
    }
    if (_tempCtrl.text.isNotEmpty) {
      payload['temperature'] = double.parse(_tempCtrl.text.trim());
    }

    final dataBase64 = base64Encode(utf8.encode(jsonEncode(payload)));

    try {
      final result = await context.read<ApiClient>().uploadHealthData(
        patientDID: auth.did,
        dataBase64: dataBase64,
        dataType: _category == 'labs' ? 'EHR' : 'WEARABLE',
        category: _category,
      );
      setState(() { _successCid = result['cid'] as String?; _loading = false; });
      _heartRateCtrl.clear();
      _spo2Ctrl.clear();
      _tempCtrl.clear();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Category selector
            Text('Category', style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'vitals', label: Text('Vitals'), icon: Icon(Icons.favorite_outline)),
                ButtonSegment(value: 'labs', label: Text('Labs'), icon: Icon(Icons.science_outlined)),
                ButtonSegment(value: 'general', label: Text('General'), icon: Icon(Icons.notes_outlined)),
              ],
              selected: {_category},
              onSelectionChanged: (s) => setState(() => _category = s.first),
            ),
            const SizedBox(height: 24),

            Text('Metrics', style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 12),

            _metricField(_heartRateCtrl, 'Heart Rate', 'bpm', Icons.favorite),
            const SizedBox(height: 12),
            _metricField(_spo2Ctrl, 'SpO₂', '%', Icons.air),
            const SizedBox(height: 12),
            _metricField(_tempCtrl, 'Temperature', '°C', Icons.thermostat),
            const SizedBox(height: 28),

            if (_successCid != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Uploaded: ${_successCid!.substring(0, 20)}…',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green)),
                    ),
                  ],
                ),
              ),

            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red))),
                  ],
                ),
              ),

            FilledButton.icon(
              onPressed: _loading ? null : _upload,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload to Vault'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricField(TextEditingController ctrl, String label, String unit, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      validator: (v) {
        if (v != null && v.isNotEmpty && double.tryParse(v.trim()) == null) {
          return 'Enter a valid number';
        }
        return null;
      },
    );
  }
}
