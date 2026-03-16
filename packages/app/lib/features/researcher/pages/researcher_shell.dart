import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/researcher_bloc.dart';
import '../../../core/api_client.dart';
import 'marketplace_page.dart';
import 'submit_request_page.dart';

class ResearcherShell extends StatefulWidget {
  const ResearcherShell({super.key});

  @override
  State<ResearcherShell> createState() => _ResearcherShellState();
}

class _ResearcherShellState extends State<ResearcherShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state as AuthAuthenticated;
    final scheme = Theme.of(context).colorScheme;
    final shortAddr = _shortAddr(auth.did);

    return BlocProvider(
      create: (ctx) =>
          ResearcherBloc(ctx.read<ApiClient>())..add(const SearchDatasets()),
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.secondary, scheme.tertiary],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.onSecondary
                                  .withValues(alpha: 0.2),
                            ),
                            child: Icon(Icons.science,
                                color: scheme.onSecondary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Researcher',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            color: scheme.onSecondary,
                                            fontWeight: FontWeight.bold)),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: auth.did));
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Address copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ));
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(shortAddr,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: scheme.onSecondary
                                                      .withValues(
                                                          alpha: 0.8))),
                                      const SizedBox(width: 4),
                                      Icon(Icons.copy,
                                          size: 12,
                                          color: scheme.onSecondary
                                              .withValues(alpha: 0.7)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.logout,
                                color: scheme.onSecondary),
                            onPressed: () =>
                                context.read<AuthBloc>().add(SignOut()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: IndexedStack(
              key: ValueKey(_tab),
              index: _tab,
              children: const [MarketplacePage(), SubmitRequestPage()],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Datasets',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'New Request',
            ),
          ],
        ),
      ),
    );
  }

  String _shortAddr(String addr) {
    if (addr.length <= 16) return addr;
    return '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}';
  }
}
