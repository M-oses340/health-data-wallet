import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/api_client.dart';

final _dateFmt = DateFormat('d MMM yyyy, HH:mm');

class ConsentsPage extends StatefulWidget {
  const ConsentsPage({super.key});

  @override
  State<ConsentsPage> createState() => _ConsentsPageState();
}

class _ConsentsPageState extends State<ConsentsPage> {
  List<dynamic> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<ApiClient>().getPendingConsents();
      setState(() { _requests = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _grant(Map<String, dynamic> req) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    try {
      await context.read<ApiClient>().grantConsent(
        patientDID: auth.did,
        contractId: req['contractId'] as String,
        researcherDID: req['researcherDID'] as String,
        dataCategory: req['dataCategory'] as String,
        computationMethod: req['computationMethod'] as String,
        permittedScope: req['permittedScope'] as String,
        accessDurationSeconds: req['accessDurationSeconds'] as int,
        dataDividendWei: req['dataDividendWei'] as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consent granted'), backgroundColor: Colors.green),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revoke(Map<String, dynamic> req) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    try {
      await context.read<ApiClient>().revokeConsent(
        contractId: req['contractId'] as String,
        patientDID: auth.did,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consent revoked'), backgroundColor: Colors.orange),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _requests.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 200), _EmptyConsents()],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ConsentCard(
                request: _requests[i] as Map<String, dynamic>,
                onGrant: () => _grant(_requests[i] as Map<String, dynamic>),
                onRevoke: () => _revoke(_requests[i] as Map<String, dynamic>),
              ),
            ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;
  const _ConsentCard({required this.request, required this.onGrant, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contractId = request['contractId'] as String? ?? '';
    final category = request['dataCategory'] as String? ?? '—';
    final method = request['computationMethod'] as String? ?? '—';
    final scope = request['permittedScope'] as String? ?? '—';
    final durationSec = request['accessDurationSeconds'] as int? ?? 0;
    final dividendWei = request['dataDividendWei'] as String? ?? '0';
    final createdAt = request['createdAt'] as int?;
    final dateStr = createdAt != null
        ? _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(createdAt).toLocal())
        : '—';

    // Convert wei to ETH for display
    final ethVal = BigInt.tryParse(dividendWei) ?? BigInt.zero;
    final ethDisplay = (ethVal.toDouble() / 1e18).toStringAsFixed(4);

    final durationDisplay = durationSec >= 86400
        ? '${(durationSec / 86400).round()} day(s)'
        : '${(durationSec / 3600).round()} hour(s)';

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(Icons.science_outlined, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(dateStr,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Text('PENDING',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: Colors.orange, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _row(context, Icons.memory_outlined, 'Method', method),
            const SizedBox(height: 6),
            _row(context, Icons.policy_outlined, 'Scope', scope),
            const SizedBox(height: 6),
            _row(context, Icons.timer_outlined, 'Duration', durationDisplay),
            const SizedBox(height: 6),
            _row(context, Icons.payments_outlined, 'Dividend', '$ethDisplay ETH'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: contractId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contract ID copied'), duration: Duration(seconds: 2)),
                );
              },
              child: _row(context, Icons.link, 'Contract',
                  contractId.length > 20
                      ? '${contractId.substring(0, 10)}…${contractId.substring(contractId.length - 8)}'
                      : contractId,
                  copyable: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Decline'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onGrant,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Grant'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value, {bool copyable = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('$label: ', style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant)),
        Expanded(
          child: Text(value,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
        if (copyable) Icon(Icons.copy, size: 11, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _EmptyConsents extends StatelessWidget {
  const _EmptyConsents();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(Icons.verified_user_outlined, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text('No pending requests',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Researcher requests will appear here.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
