import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_data_wallet/features/patient/bloc/patient_bloc.dart';
import '../mocks/mock_api_client.dart';

void main() {
  late MockApiClient api;
  const did = 'did:ethr:0xPAT';

  setUp(() => api = MockApiClient());

  group('LoadPatientData', () {
    final payments = [
      {'eventType': 'DIVIDEND_PAID', 'amount': '0.01', 'contractId': 'c1', 'timestamp': 1700000000}
    ];
    final auditEntries = [
      {'eventType': 'CONSENT_GRANTED', 'contractId': 'c1', 'timestamp': 1700000000},
      {'eventType': 'DATA_ANONYMIZED', 'contractId': 'c1', 'timestamp': 1700000001},
    ];

    blocTest<PatientBloc, PatientState>(
      'emits [PatientLoading, PatientLoaded] on success',
      build: () {
        when(() => api.getPayments(did))
            .thenAnswer((_) async => {'payments': payments});
        when(() => api.getAuditTrail(did))
            .thenAnswer((_) async => {'entries': auditEntries});
        return PatientBloc(api);
      },
      act: (bloc) => bloc.add(const LoadPatientData(did)),
      expect: () => [
        PatientLoading(),
        PatientLoaded(payments: payments, auditTrail: auditEntries),
      ],
    );

    blocTest<PatientBloc, PatientState>(
      'emits [PatientLoading, PatientLoaded] with empty lists when API returns empty',
      build: () {
        when(() => api.getPayments(did))
            .thenAnswer((_) async => {'payments': []});
        when(() => api.getAuditTrail(did))
            .thenAnswer((_) async => {'entries': []});
        return PatientBloc(api);
      },
      act: (bloc) => bloc.add(const LoadPatientData(did)),
      expect: () => [
        PatientLoading(),
        const PatientLoaded(payments: [], auditTrail: []),
      ],
    );

    blocTest<PatientBloc, PatientState>(
      'emits [PatientLoading, PatientError] when API throws',
      build: () {
        when(() => api.getPayments(did)).thenThrow(Exception('network error'));
        when(() => api.getAuditTrail(did))
            .thenAnswer((_) async => {'entries': []});
        return PatientBloc(api);
      },
      act: (bloc) => bloc.add(const LoadPatientData(did)),
      expect: () => [PatientLoading(), isA<PatientError>()],
    );
  });
}
