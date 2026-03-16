import 'package:flutter/material.dart';
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
    return BlocProvider(
      create: (ctx) =>
          ResearcherBloc(ctx.read<ApiClient>())..add(const SearchDatasets()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Researcher Marketplace'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthBloc>().add(SignOut()),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [MarketplacePage(), SubmitRequestPage()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.search), label: 'Datasets'),
            NavigationDestination(
                icon: Icon(Icons.add_circle_outline), label: 'New Request'),
          ],
        ),
      ),
    );
  }
}
