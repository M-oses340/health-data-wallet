import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:health_data_wallet/features/researcher/bloc/researcher_bloc.dart';
import '../mocks/mock_api_client.dart';

void main() {
  late MockApiClient api;

  setUp(() => api = MockApiClient());

  // ---------------------------------------------------------------------------
  // SearchDatasets
  // ---------------------------------------------------------------------------

  group('SearchDatasets', () {
    final datasets = [
      {'listingId': 'l1', 'category': 'cardiology', 'dataType': 'EHR', 'recordCount': 5},
      {'listingId': 'l2', 'category': 'vitals', 'dataType': 'WEARABLE', 'recordCount': 10},
    ];

    blocTest<ResearcherBloc, ResearcherState>(
      'emits [ResearcherLoading, DatasetsLoaded] on success',
      build: () {
        when(() => api.searchDatasets(
              category: any(named: 'category'),
              dataType: any(named: 'dataType'),
            )).thenAnswer((_) async => datasets);
        return ResearcherBloc(api);
      },
      act: (bloc) => bloc.add(const SearchDatasets()),
      expect: () => [ResearcherLoading(), DatasetsLoaded(datasets)],
    );

    blocTest<ResearcherBloc, ResearcherState>(
      'emits [ResearcherLoading, DatasetsLoaded] with category filter',
      build: () {
        final filtered = [datasets[0]];
        when(() => api.searchDatasets(
              category: 'cardiology',
              dataType: any(named: 'dataType'),
            )).thenAnswer((_) async => filtered);
        return ResearcherBloc(api);
      },
      act: (bloc) => bloc.add(const SearchDatasets(category: 'cardiology')),
      expect: () => [
        ResearcherLoading(),
        DatasetsLoaded([datasets[0]]),
      ],
    );

    blocTest<ResearcherBloc, ResearcherState>(
      'emits [ResearcherLoading, ResearcherError] when API throws',
      build: () {
        when(() => api.searchDatasets(
              category: any(named: 'category'),
              dataType: any(named: 'dataType'),
            )).thenThrow(Exception('timeout'));
        return ResearcherBloc(api);
      },
      act: (bloc) => bloc.add(const SearchDatasets()),
      expect: () => [ResearcherLoading(), isA<ResearcherError>()],
    );
  });

  // ---------------------------------------------------------------------------
  // SubmitRequest
  // ---------------------------------------------------------------------------

  group('SubmitRequest', () {
    final payload = {
      'researcherDID': 'did:ethr:0xRES',
      'dataCategory': 'cardiology',
      'computationMethod': 'FEDERATED_LEARNING',
      'permittedScope': 'cardio-research',
      'accessDurationSeconds': 86400,
      'dataDividendWei': '100000000000000000',
    };

    blocTest<ResearcherBloc, ResearcherState>(
      'emits [ResearcherLoading, RequestSubmitted] on success',
      build: () {
        when(() => api.submitComputationRequest(any())).thenAnswer(
            (_) async => {'status': 'ACCEPTED', 'contractId': 'contract-abc'});
        return ResearcherBloc(api);
      },
      act: (bloc) => bloc.add(SubmitRequest(payload)),
      expect: () => [
        ResearcherLoading(),
        const RequestSubmitted('contract-abc'),
      ],
    );

    blocTest<ResearcherBloc, ResearcherState>(
      'emits [ResearcherLoading, ResearcherError] when submission fails',
      build: () {
        when(() => api.submitComputationRequest(any()))
            .thenThrow(Exception('400 Bad Request'));
        return ResearcherBloc(api);
      },
      act: (bloc) => bloc.add(SubmitRequest(payload)),
      expect: () => [ResearcherLoading(), isA<ResearcherError>()],
    );
  });
}
