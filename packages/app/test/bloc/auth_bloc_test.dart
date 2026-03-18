import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_data_wallet/core/api_client.dart';
import 'package:health_data_wallet/features/auth/bloc/auth_bloc.dart';
import '../mocks/mock_api_client.dart';

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
  });

  // ---------------------------------------------------------------------------
  // RegisterPatient
  // ---------------------------------------------------------------------------

  group('RegisterPatient', () {
    const did = 'did:ethr:0xABC';
    const wallet = '0xABC';
    const token = 'header.body.sig';

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on success',
      build: () {
        when(() => api.registerPatient()).thenAnswer((_) async => {
              'did': did,
              'walletAddress': wallet,
              'token': token,
            });
        when(() => api.setAuthToken(any())).thenReturn(null);
        return AuthBloc(api);
      },
      act: (bloc) => bloc.add(RegisterPatient()),
      expect: () => [
        AuthLoading(),
        const AuthAuthenticated(UserRole.patient, did, walletAddress: wallet),
      ],
      verify: (_) {
        verify(() => api.setAuthToken(token)).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when API throws',
      build: () {
        when(() => api.registerPatient())
            .thenThrow(Exception('network error'));
        return AuthBloc(api);
      },
      act: (bloc) => bloc.add(RegisterPatient()),
      expect: () => [
        AuthLoading(),
        isA<AuthError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // RegisterResearcher
  // ---------------------------------------------------------------------------

  group('RegisterResearcher', () {
    const did = 'did:ethr:0xRES';
    const token = 'header.body.sig';

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on success',
      build: () {
        when(() => api.registerResearcher(organisation: any(named: 'organisation')))
            .thenAnswer((_) async => {
                  'did': did,
                  'walletAddress': '0xRES',
                  'token': token,
                });
        when(() => api.setAuthToken(any())).thenReturn(null);
        return AuthBloc(api);
      },
      act: (bloc) =>
          bloc.add(const RegisterResearcher(organisation: 'BioLab')),
      expect: () => [
        AuthLoading(),
        const AuthAuthenticated(UserRole.researcher, did,
            walletAddress: '0xRES'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoginWithDID
  // ---------------------------------------------------------------------------

  group('LoginWithDID', () {
    const did = 'did:ethr:0xPAT';
    const token = 'header.body.sig';

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on success',
      build: () {
        when(() => api.login(did, 'patient'))
            .thenAnswer((_) async => {'token': token});
        when(() => api.setAuthToken(any())).thenReturn(null);
        return AuthBloc(api);
      },
      act: (bloc) => bloc.add(const LoginWithDID(did, UserRole.patient)),
      expect: () => [
        AuthLoading(),
        const AuthAuthenticated(UserRole.patient, did),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when login fails',
      build: () {
        when(() => api.login(any(), any()))
            .thenThrow(Exception('401 Unauthorized'));
        return AuthBloc(api);
      },
      act: (bloc) =>
          bloc.add(const LoginWithDID('did:ethr:0xBAD', UserRole.patient)),
      expect: () => [AuthLoading(), isA<AuthError>()],
    );
  });

  // ---------------------------------------------------------------------------
  // SignOut
  // ---------------------------------------------------------------------------

  group('SignOut', () {
    blocTest<AuthBloc, AuthState>(
      'emits AuthInitial and clears token',
      build: () {
        when(() => api.clearAuthToken()).thenReturn(null);
        return AuthBloc(api);
      },
      seed: () =>
          const AuthAuthenticated(UserRole.patient, 'did:ethr:0xPAT'),
      act: (bloc) => bloc.add(SignOut()),
      expect: () => [AuthInitial()],
      verify: (_) => verify(() => api.clearAuthToken()).called(1),
    );
  });
}
