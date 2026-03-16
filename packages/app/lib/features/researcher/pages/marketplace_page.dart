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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Search bar area
        Container(
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              TextField(
                controller: _categoryCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by category (e.g. cardiology)',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _TypeChip(
                            label: 'All',
                            selected: _selectedType == null,
                            onTap: () =>
                                setState(() => _selectedType = null),
                          ),
                          ..._dataTypes.map((t) => _TypeChip(
                                label: t,
                                selected: _selectedType == t,
                                onTap: () =>
                                    setState(() => _selectedType = t),
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _search,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Search'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<ResearcherBloc, ResearcherState>(
            builder: (context, state) {
              if (state is ResearcherLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ResearcherError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('Error: ${state.message}'),
                    ],
                  ),
                );
              }
              if (state is DatasetsLoaded) {
                if (state.datasets.isEmpty) {
                  return _EmptySearch();
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.datasets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _DatasetCard(
                      dataset: state.datasets[i] as Map<String, dynamic>),
                );
              }
              return _SearchPrompt();
            },
          ),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
          ),
        ),
      ),
    );
  }
}

class _DatasetCard extends StatelessWidget {
  final Map<String, dynamic> dataset;
  const _DatasetCard({required this.dataset});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = dataset['category']?.toString() ?? '—';
    final dataType = dataset['dataType']?.toString() ?? '';
    final recordCount = dataset['recordCount']?.toString() ?? '0';
    final minQuality = dataset['minQualityScore']?.toString() ?? '0';
    final methods =
        (dataset['availableMethods'] as List?)?.cast<String>() ?? [];

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(Icons.dataset_outlined,
                      color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (dataType.isNotEmpty)
                        Text(dataType,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatBadge(
                    icon: Icons.people_outline,
                    label: '$recordCount records'),
                const SizedBox(width: 8),
                _StatBadge(
                    icon: Icons.star_outline,
                    label: 'Quality ≥ $minQuality'),
              ],
            ),
            if (methods.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: methods
                    .map((m) => _MethodTag(label: m))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

class _MethodTag extends StatelessWidget {
  final String label;
  const _MethodTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              )),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
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
            child: Icon(Icons.manage_search,
                size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text('Search for datasets',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No datasets found.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}
