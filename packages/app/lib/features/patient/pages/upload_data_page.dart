import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/api_client.dart';

class UploadDataPage extends StatefulWidget {
  const UploadDataPage({super.key});

  @override
  State<UploadDataPage> createState() => _UploadDataPageState();
}

class _UploadDataPageState extends State<UploadDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          color: scheme.surface,
          child: TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(icon: Icon(Icons.edit_outlined), text: 'Manual entry'),
              Tab(icon: Icon(Icons.folder_open_outlined), text: 'From file'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _ManualEntryTab(),
              _FilePickerTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Manual entry tab (original form)
// ---------------------------------------------------------------------------

class _ManualEntryTab extends StatefulWidget {
  const _ManualEntryTab();

  @override
  State<_ManualEntryTab> createState() => _ManualEntryTabState();
}

class _ManualEntryTabState extends State<_ManualEntryTab> {
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
    final allEmpty = _heartRateCtrl.text.isEmpty &&
        _spo2Ctrl.text.isEmpty &&
        _tempCtrl.text.isEmpty;
    if (allEmpty) {
      setState(() => _error = 'Please enter at least one metric value.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _successCid = null; });

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final auth = authState;
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
      HapticFeedback.lightImpact();
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
              _banner(Colors.green, Icons.check_circle_outline,
                  'Uploaded: ${_successCid!.substring(0, 20)}…'),
            if (_error != null)
              _banner(Colors.red, Icons.error_outline, _error!),
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

  Widget _banner(Color color, IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File picker tab
// ---------------------------------------------------------------------------

class _FilePickerTab extends StatefulWidget {
  const _FilePickerTab();

  @override
  State<_FilePickerTab> createState() => _FilePickerTabState();
}

class _FilePickerTabState extends State<_FilePickerTab> {
  String _category = 'vitals';
  PlatformFile? _pickedFile;
  bool _loading = false;
  String? _successCid;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt', 'csv'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() { _pickedFile = result.files.first; _successCid = null; _error = null; });
    }
  }

  Future<void> _upload() async {
    final file = _pickedFile;
    if (file == null) return;
    setState(() { _loading = true; _error = null; _successCid = null; });

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final auth = authState;
    final apiClient = context.read<ApiClient>();

    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final dataBase64 = base64Encode(bytes);
      final result = await apiClient.uploadHealthData(
        patientDID: auth.did,
        dataBase64: dataBase64,
        dataType: _category == 'labs' ? 'EHR' : 'WEARABLE',
        category: _category,
      );
      setState(() { _successCid = result['cid'] as String?; _loading = false; _pickedFile = null; });
      HapticFeedback.lightImpact();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = _pickedFile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

          // Drop zone / pick button
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: file != null ? scheme.primary : scheme.outlineVariant,
                  width: file != null ? 2 : 1,
                  style: BorderStyle.solid,
                ),
              ),
              child: file != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.insert_drive_file_outlined,
                            size: 36, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text(file.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          '${(file.size / 1024).toStringAsFixed(1)} KB',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _pickFile,
                          child: const Text('Change file'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_outlined,
                            size: 40, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text('Tap to pick a file',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('JSON, TXT or CSV',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),

          if (_successCid != null)
            _banner(Colors.green, Icons.check_circle_outline,
                'Uploaded: ${_successCid!.substring(0, 20)}…'),
          if (_error != null)
            _banner(Colors.red, Icons.error_outline, _error!),

          FilledButton.icon(
            onPressed: (file == null || _loading) ? null : _upload,
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
    );
  }

  Widget _banner(Color color, IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
        ],
      ),
    );
  }
}
