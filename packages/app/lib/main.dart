import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/api_client.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/patient/bloc/patient_bloc.dart';
import 'features/researcher/bloc/researcher_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ApiClient()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) {
              final api = ctx.read<ApiClient>();
              final bloc = AuthBloc(api)..add(RestoreSession());
              api.onSessionExpired = () => bloc.add(SignOut());
              return bloc;
            },
          ),
          BlocProvider(
            create: (ctx) => PatientBloc(ctx.read<ApiClient>()),
          ),
          BlocProvider(
            create: (ctx) => ResearcherBloc(ctx.read<ApiClient>()),
          ),
        ],
        child: const HealthDataApp(),
      ),
    ),
  );
}
