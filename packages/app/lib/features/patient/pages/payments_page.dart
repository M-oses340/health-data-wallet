import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/patient_bloc.dart';

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientBloc, PatientState>(
      builder: (context, state) {
        if (state is PatientLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PatientError) {
          return _errorView(context, state.message);
        }
        if (state is PatientLoaded) {
          return _loaded(context, state.payments);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _loaded(BuildContext context, List payments) {
    final scheme = Theme.of(context).colorScheme;

    // Compute total
    double total = 0;
    for (final p in payments) {
      final raw = (p as Map<String, dynamic>)['amount'];
      if (raw != null) total += double.tryParse(raw.toString()) ?? 0;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _summaryCard(context, scheme, total, payments.length),
          ),
        ),
        if (payments.isEmpty)
          const SliverFillRemaining(child: _EmptyState(
            icon: Icons.payments_outlined,
            message: 'No payments yet.\nYour earnings will appear here.',
          ))
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: payments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  _PaymentCard(payment: payments[i] as Map<String, dynamic>),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, ColorScheme scheme, double total,
      int count) {
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Error: $message',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = payment['amount']?.toString() ?? '—';
    final contractId = payment['contractId']?.toString() ?? '—';
    final ts = payment['timestamp'];
    final dateStr = ts != null
        ? DateTime.fromMillisecondsSinceEpoch((ts as int) * 1000)
            .toLocal()
            .toString()
            .substring(0, 16)
        : '—';

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          )),
                  const SizedBox(height: 2),
                  Text(
                    contractId.length > 20
                        ? '${contractId.substring(0, 10)}…${contractId.substring(contractId.length - 6)}'
                        : contractId,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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
      ),
    );
  }
}

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
