import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/patient_bloc.dart';

class AuditTrailPage extends StatelessWidget {
  const AuditTrailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientBloc, PatientState>(
      builder: (context, state) {
        if (state is PatientLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PatientError) {
          return Center(child: Text('Error: ${state.message}'));
        }
        if (state is PatientLoaded) {
          final entries = state.auditTrail;
          if (entries.isEmpty) {
            return const Center(child: Text('No audit entries yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final e = entries[i] as Map<String, dynamic>;
              return ListTile(
                leading: _icon(e['eventType'] as String?),
                title: Text(e['eventType'] ?? '—'),
                subtitle: e['contractId'] != null
                    ? Text('Contract: ${e['contractId']}')
                    : null,
                trailing: Text(
                  e['timestamp'] != null
                      ? DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int)
                          .toLocal()
                          .toString()
                          .substring(0, 16)
                      : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _icon(String? eventType) {
    switch (eventType) {
      case 'CONSENT_GRANTED':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'CONSENT_REVOKED':
        return const Icon(Icons.cancel, color: Colors.red);
      case 'DIVIDEND_PAID':
        return const Icon(Icons.payments, color: Colors.blue);
      case 'DATA_ANONYMIZED':
        return const Icon(Icons.security, color: Colors.orange);
      default:
        return const Icon(Icons.info_outline);
    }
  }
}
