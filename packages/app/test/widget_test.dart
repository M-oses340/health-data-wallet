import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_data_wallet/app.dart';
import 'package:health_data_wallet/core/api_client.dart';
import 'package:health_data_wallet/features/auth/bloc/auth_bloc.dart';

void main() {
  testWidgets('Role select page renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => ApiClient()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (ctx) => AuthBloc(ctx.read<ApiClient>())),
          ],
          child: const HealthDataApp(),
        ),
      ),
    );

    expect(find.text('Health Data Wallet'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });
}
