import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/researcher_bloc.dart';

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
              content: Text('Computation started — job: ${state.job['job']?['jobId'] ?? 'running'}'),
              backgroundColor: Colors.green,
            ),
          );
          ctx.read<ResearcherBloc>().add(const LoadActiveContracts());
        } else if (state is ResearcherError) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
          ctx.read<ResearcherBloc>().add(const LoadActiveContracts());
        }
      },
      builder: (ctx, state) {
        if (state is ResearcherLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final contracts = state is ActiveContractsLoaded ? state.contracts : <dynamic>[];

        return RefreshIndicator(
          onRefresh: () async => ctx.read<ResearcherBloc>().add(const LoadActiveContracts()),
          child: contracts.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('No active contracts yet',
                              style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 4),
                          Text('Waiting for patients to grant consent',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: contracts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final c = contracts[i] as Map<String, dynamic>;
                    return _ContractCard(contract: c);
                  },
                ),
        );
      },
    );
  }
}

class _ContractCard extends StatelessWidget {
  final Map<String, dynamic> contract;
  const _ContractCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contractId = contract['contractId'] as String? ?? '';
    final category = contract['dataCategory'] as String? ?? '';
    final method = contract['computationMethod'] as String? ?? '';
    final dividendWei = contract['dataDividendWei'] as String? ?? '0';
    final dividendEth = (BigInt.tryParse(dividendWei) ?? BigInt.zero) /
        BigInt.from(10).pow(18);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                        color: scheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(category.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(method, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              '${contractId.substring(0, 10)}…${contractId.substring(contractId.length - 8)}',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _RunButton(contract: contract),
          ],
        ),
      ),
    );
  }
}

class _RunButton extends StatefulWidget {
  final Map<String, dynamic> contract;
  const _RunButton({required this.contract});

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  final _didController = TextEditingController();

  @override
  void dispose() {
    _didController.dispose();
    super.dispose();
  }

  void _run(BuildContext context) {
    final patientDID = _didController.text.trim();
    if (patientDID.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a patient DID to run computation')),
      );
      return;
    }
    context.read<ResearcherBloc>().add(RunComputation(
          contractId: widget.contract['contractId'] as String,
          patientDID: patientDID,
        ));
  }

  @override
  Widget build(BuildContext context) {
    // Pre-fill with the auth DID if researcher wants to test with their own
    final authState = context.watch<AuthBloc>().state;
    final hint = authState is AuthAuthenticated ? 'did:ethr:0x…' : 'did:ethr:0x…';

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _didController,
            decoration: InputDecoration(
              hintText: hint,
              labelText: 'Patient DID',
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _run(context),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Run'),
        ),
      ],
    );
  }
}
