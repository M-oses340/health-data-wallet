import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/api_client.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/patient/bloc/patient_bloc.dart';
import 'features/researcher/bloc/researcher_bloc.dart';

void main() {
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ApiClient()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => AuthBloc(ctx.read<ApiClient>()),
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
