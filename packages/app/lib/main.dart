import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/api_client.dart';
import 'features/auth/bloc/auth_bloc.dart';

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
        ],
        child: const HealthDataApp(),
      ),
    ),
  );
}
