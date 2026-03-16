import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/patient_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';

class AuditTrailPage extends StatelessWidget {
  const AuditTrailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientBloc, PatientState>(
      builder: (context, state) {
        if (state is PatientLoading || state is PatientInitial) {
          return _SkeletonTimeline();
        }
        if (state is PatientError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Error: ${state.message}'),
              ],
            ),
          );
        }
        if (state is PatientLoaded) {
          final entries = state.auditTrail;
          final auth =
              context.read<AuthBloc>().state as AuthAuthenticated;

          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                context
                    .read<PatientBloc>()
                    .add(LoadPatientData(auth.did));
                await context.read<PatientBloc>().stream.firstWhere(
                    (s) => s is PatientLoaded || s is PatientError);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  _EmptyAudit(),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<PatientBloc>().add(LoadPatientData(auth.did));
              await context.read<PatientBloc>().stream.firstWhere(
                  (s) => s is PatientLoaded || s is PatientError);
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i] as Map<String, dynamic>;
                final isLast = i == entries.length - 1;
                return _TimelineEntry(entry: e, isLast: isLast);
              },
            ),
          );
        }
        return _SkeletonTimeline();
      },
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isLast;
  const _TimelineEntry({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eventType = entry['eventType'] as String? ?? 'UNKNOWN';
    final config = _eventConfig(eventType);
    final contractId = entry['contractId']?.toString();
    final ts = entry['timestamp'];
    final dateStr = ts != null
        ? DateTime.fromMillisecondsSinceEpoch(ts as int)
            .toLocal()
            .toString()
            .substring(0, 16)
        : '—';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: config.color.withValues(alpha: 0.15),
                  ),
                  child: Icon(config.icon, size: 18, color: config.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Card(
                elevation: 0,
                color:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _EventChip(
                                label: eventType, color: config.color),
                          ),
                          Text(dateStr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      if (contractId != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: contractId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Contract ID copied'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(Icons.link,
                                  size: 13,
                                  color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  contractId.length > 24
                                      ? '${contractId.substring(0, 12)}…${contractId.substring(contractId.length - 8)}'
                                      : contractId,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.copy,
                                  size: 12,
                                  color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _EventConfig _eventConfig(String type) {
    switch (type) {
      case 'CONSENT_GRANTED':
        return const _EventConfig(Icons.check_circle_outline, Colors.green);
      case 'CONSENT_REVOKED':
        return const _EventConfig(Icons.cancel_outlined, Colors.red);
      case 'DIVIDEND_PAID':
        return const _EventConfig(Icons.payments_outlined, Colors.blue);
      case 'DATA_ANONYMIZED':
        return const _EventConfig(Icons.security, Colors.orange);
      case 'DATA_ACCESSED':
        return const _EventConfig(Icons.visibility_outlined, Colors.purple);
      default:
        return const _EventConfig(Icons.info_outline, Colors.grey);
    }
  }
}

class _EventConfig {
  final IconData icon;
  final Color color;
  const _EventConfig(this.icon, this.color);
}

class _EventChip extends StatelessWidget {
  final String label;
  final Color color;
  const _EventChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

class _SkeletonTimeline extends StatefulWidget {
  @override
  State<_SkeletonTimeline> createState() => _SkeletonTimelineState();
}

class _SkeletonTimelineState extends State<_SkeletonTimeline>
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
          children: List.generate(
            5,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: opacity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyAudit extends StatelessWidget {
  const _EmptyAudit();

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
            child: Icon(Icons.history, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text('No audit entries yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 4),
          Text('Activity on your data will appear here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}
