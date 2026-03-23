import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/researcher_bloc.dart';

final _dateFmt = DateFormat('d MMM yyyy');

class ActiveContractsPage extends StatefulWidget {
  const ActiveContractsPage({super.key});

  @override
  State<ActiveContractsPage> createState() => _ActiveContractsPageState();
}

class _ActiveContractsPageState extends State<ActiveContractsPage> {
  @override
  void initState() {
    super.initState();
    context.read<ResearcherBloc>().add(const LoadActiveContracts());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ResearcherBloc, ResearcherState>(
      listener: (ctx, state) {
        if (state is ComputationStarted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Computation complete — job: ${state.job['job']?['jobId']?.toString().substring(0, 8) ?? 'done'}…',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
          ctx.read<ResearcherBloc>().add(const LoadActiveContracts());
        } else if (state is ResearcherError) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          ctx.read<ResearcherBloc>().add(const LoadActiveContracts());
        }
      },
      builder: (ctx, state) {
        if (state is ResearcherLoading) {
          return _SkeletonList();
        }

        final contracts =
            state is ActiveContractsLoaded ? state.contracts : <dynamic>[];

        return RefreshIndicator(
          onRefresh: () async =>
              ctx.read<ResearcherBloc>().add(const LoadActiveContracts()),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (contracts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: _SummaryCard(contracts: contracts),
                  ),
                ),
              if (contracts.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: contracts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _ContractCard(
                      contract: contracts[i] as Map<String, dynamic>,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final List<dynamic> contracts;
  const _SummaryCard({required this.contracts});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double totalEth = 0;
    for (final c in contracts) {
      final wei = (c as Map<String, dynamic>)['dataDividendWei'] as String? ?? '0';
      totalEth += (BigInt.tryParse(wei) ?? BigInt.zero).toDouble() / 1e18;
    }

    return Container(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Contracts',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondary.withValues(alpha: 0.8),
                        )),
                const SizedBox(height: 4),
                Text('${contracts.length}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                            color: scheme.onSecondary,
                            fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Total committed: ${totalEth.toStringAsFixed(4)} ETH',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondary.withValues(alpha: 0.7),
                        )),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSecondary.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.science, color: scheme.onSecondary, size: 26),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contract card
// ---------------------------------------------------------------------------

class _ContractCard extends StatelessWidget {
  final Map<String, dynamic> contract;
  const _ContractCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contractId = contract['contractId'] as String? ?? '';
    final category = contract['dataCategory'] as String? ?? '—';
    final method = contract['computationMethod'] as String? ?? '—';
    final scope = contract['permittedScope'] as String? ?? '—';
    final dividendWei = contract['dataDividendWei'] as String? ?? '0';
    final createdAt = contract['createdAt'] as int?;
    final accessSecs = contract['accessDurationSeconds'] as int? ?? 0;

    final dividendEth =
        (BigInt.tryParse(dividendWei) ?? BigInt.zero).toDouble() / 1e18;
    final shortId = contractId.length > 18
        ? '${contractId.substring(0, 10)}…${contractId.substring(contractId.length - 8)}'
        : contractId;
    final createdStr = createdAt != null
        ? _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '—';
    final durationStr = _formatDuration(accessSecs);

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('ACTIVE',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text('${dividendEth.toStringAsFixed(4)} ETH',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),

            // Category + method
            Text(category.toUpperCase(),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.memory_outlined,
                    size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(method,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Icon(Icons.policy_outlined,
                    size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(scope,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Meta row
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(createdStr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Icon(Icons.timer_outlined,
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(durationStr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),

            // Contract ID with copy
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: contractId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contract ID copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(shortId,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 11, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Run button
            _RunButton(contract: contract),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds >= 86400) return '${(seconds / 86400).round()} days';
    if (seconds >= 3600) return '${(seconds / 3600).round()} hours';
    return '${(seconds / 60).round()} min';
  }
}

// ---------------------------------------------------------------------------
// Run button with confirmation dialog
// ---------------------------------------------------------------------------

class _RunButton extends StatefulWidget {
  final Map<String, dynamic> contract;
  const _RunButton({required this.contract});

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  bool _running = false;

  Future<void> _confirm(BuildContext context) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final contractId = widget.contract['contractId'] as String? ?? '';
    final category = widget.contract['dataCategory'] as String? ?? '';
    final dividendWei =
        widget.contract['dataDividendWei'] as String? ?? '0';
    final dividendEth =
        (BigInt.tryParse(dividendWei) ?? BigInt.zero).toDouble() / 1e18;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run computation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dataset: $category'),
            const SizedBox(height: 4),
            Text('Dividend: ${dividendEth.toStringAsFixed(4)} ETH'),
            const SizedBox(height: 8),
            const Text(
              'This will trigger the computation and release the dividend to the patient.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Run'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _running = true);
    context.read<ResearcherBloc>().add(RunComputation(
          contractId: contractId,
          patientDID: authState.did,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _running ? null : () => _confirm(context),
        icon: _running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow, size: 18),
        label: Text(_running ? 'Running…' : 'Run Computation'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loader
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
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: scheme.secondary.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              3,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  height: 180,
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
  const _EmptyState();

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
              color: scheme.secondary.withValues(alpha: 0.08),
            ),
            child: Icon(Icons.hourglass_empty,
                size: 40, color: scheme.secondary),
          ),
          const SizedBox(height: 16),
          Text('No active contracts yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Waiting for patients to grant consent.\nPull down to refresh.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
