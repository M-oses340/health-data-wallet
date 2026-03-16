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
          return Center(child: Text('Error: ${state.message}'));
        }
        if (state is PatientLoaded) {
          final payments = state.payments;
          if (payments.isEmpty) {
            return const Center(child: Text('No payments yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final p = payments[i] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.monetization_on, color: Colors.green),
                title: Text('${p['amount'] ?? '—'} ETH'),
                subtitle: Text('Contract: ${p['contractId'] ?? '—'}'),
                trailing: Text(
                  p['timestamp'] != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                              (p['timestamp'] as int) * 1000)
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
}
