import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/researcher_bloc.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _categoryCtrl = TextEditingController();
  String? _selectedType;

  final _dataTypes = ['EHR', 'WEARABLE', 'GENETIC'];

  @override
  void dispose() {
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _search() {
    context.read<ResearcherBloc>().add(SearchDatasets(
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          dataType: _selectedType,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                hint: const Text('Type'),
                value: _selectedType,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ..._dataTypes.map((t) =>
                      DropdownMenuItem(value: t, child: Text(t))),
                ],
                onChanged: (v) => setState(() => _selectedType = v),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _search, child: const Text('Search')),
            ],
          ),
        ),
        Expanded(
          child: BlocBuilder<ResearcherBloc, ResearcherState>(
            builder: (context, state) {
              if (state is ResearcherLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ResearcherError) {
                return Center(child: Text('Error: ${state.message}'));
              }
              if (state is DatasetsLoaded) {
                if (state.datasets.isEmpty) {
                  return const Center(child: Text('No datasets found.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: state.datasets.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final d = state.datasets[i] as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.dataset),
                      title: Text(d['category'] ?? '—'),
                      subtitle: Text(
                          '${d['dataType'] ?? ''} · ${d['recordCount'] ?? 0} records · min quality ${d['minQualityScore'] ?? 0}'),
                      trailing: Text(
                        (d['availableMethods'] as List?)?.join(', ') ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                );
              }
              return const Center(child: Text('Search for datasets above.'));
            },
          ),
        ),
      ],
    );
  }
}
