import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../bloc/patient_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/api_client.dart';

final _dateFmt = DateFormat('d MMM yyyy, HH:mm');

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientBloc, PatientState>(
      builder: (context, state) {
        if (state is PatientLoading || state is PatientInitial) {
          return _SkeletonList();
        }
        if (state is PatientError) {
          return _errorView(context, state.message);
        }
        if (state is PatientLoaded) {
          return _loaded(context, state);
        }
        return _SkeletonList();
      },
    );
  }

  Widget _loaded(BuildContext context, PatientLoaded state) {
    final scheme = Theme.of(context).colorScheme;
    final payments = state.payments;

    double total = 0;
    for (final p in payments) {
      final raw = (p as Map<String, dynamic>)['amount'];
      if (raw != null) total += double.tryParse(raw.toString()) ?? 0;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return const SizedBox.shrink();
    final auth = authState;

    return RefreshIndicator(
      onRefresh: () async {
        context.read<PatientBloc>().add(LoadPatientData(auth.did));
        await context.read<PatientBloc>().stream
            .firstWhere((s) => s is PatientLoaded || s is PatientError);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _summaryCard(context, scheme, total, payments.length),
            ),
          ),
          if (payments.isEmpty)
            const SliverFillRemaining(
              child: _EmptyState(
                icon: Icons.payments_outlined,
                message: 'No payments yet.\nYour earnings will appear here.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: payments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PaymentCard(
                    payment: payments[i] as Map<String, dynamic>,
                    patientDid: auth.did),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _summaryCard(
      BuildContext context, ColorScheme scheme, double total, int count) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Earned',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.8),
                        )),
                const SizedBox(height: 4),
                Text('${total.toStringAsFixed(4)} ETH',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            )),
                const SizedBox(height: 4),
                Text('$count payment${count == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.7),
                        )),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onPrimary.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.account_balance_wallet,
                color: scheme.onPrimary, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context, String message) {
    final authState = context.read<AuthBloc>().state;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Error: $message',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (authState is AuthAuthenticated)
            FilledButton(
              onPressed: () => context
                  .read<PatientBloc>()
                  .add(LoadPatientData(authState.did)),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment card with copy-to-clipboard and consent revoke
// ---------------------------------------------------------------------------

class _PaymentCard extends StatefulWidget {
  final Map<String, dynamic> payment;
  final String patientDid;
  const _PaymentCard({required this.payment, required this.patientDid});

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _revoking = false;

  Future<void> _revoke(BuildContext context) async {
    final contractId = widget.payment['contractId']?.toString();
    if (contractId == null) return;

    // Capture blocs before any await
    final apiClient = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final patientBloc = context.read<PatientBloc>();
    final authBloc = context.read<AuthBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke consent?'),
        content: const Text(
            'This will revoke the researcher\'s access to your data for this contract.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _revoking = true);
    try {
      await apiClient.revokeConsent(
        contractId: contractId,
        patientDID: widget.patientDid,
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Consent revoked'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        final authState = authBloc.state;
        if (authState is AuthAuthenticated) {
          patientBloc.add(LoadPatientData(authState.did));
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to revoke: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = widget.payment['amount']?.toString() ?? '—';
    final contractId = widget.payment['contractId']?.toString() ?? '—';
    final ts = widget.payment['timestamp'];
    final dateStr = ts != null
        ? _dateFmt.format(
            DateTime.fromMillisecondsSinceEpoch((ts as int) * 1000).toLocal())
        : '—';

    final shortId = contractId.length > 20
        ? '${contractId.substring(0, 10)}…${contractId.substring(contractId.length - 6)}'
        : contractId;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: AbsorbPointer(
        absorbing: _revoking,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.arrow_downward,
                      color: Colors.green, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$amount ETH',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              )),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Clipboard.setData(ClipboardData(text: contractId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Contract ID copied'),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(shortId,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                            const SizedBox(width: 4),
                            Icon(Icons.copy,
                                size: 12, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(dateStr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ],
            ),
            const SizedBox(height: 10),
            if (contractId != '—' && widget.payment['contractId'] != null)
              Align(
                alignment: Alignment.centerRight,
                child: _revoking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Semantics(
                        label: 'Revoke consent for contract $shortId',
                        child: OutlinedButton.icon(
                          onPressed: () => _revoke(context),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Revoke consent'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton shimmer loader
// ---------------------------------------------------------------------------

class _SkeletonList extends StatefulWidget {
  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.3 + _anim.value * 0.4;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary card skeleton
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: opacity),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}
