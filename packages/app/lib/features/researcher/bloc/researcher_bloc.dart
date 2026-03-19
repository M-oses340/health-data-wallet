import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/api_client.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ResearcherEvent extends Equatable {
  const ResearcherEvent();
  @override
  List<Object?> get props => [];
}

class SearchDatasets extends ResearcherEvent {
  final String? category;
  final String? dataType;
  const SearchDatasets({this.category, this.dataType});
  @override
  List<Object?> get props => [category, dataType];
}

class SubmitRequest extends ResearcherEvent {
  final Map<String, dynamic> payload;
  const SubmitRequest(this.payload);
  @override
  List<Object?> get props => [payload];
}

class SelectDataset extends ResearcherEvent {
  final Map<String, dynamic> dataset;
  const SelectDataset(this.dataset);
  @override
  List<Object?> get props => [dataset];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class ResearcherState extends Equatable {
  const ResearcherState();
  @override
  List<Object?> get props => [];
}

class ResearcherInitial extends ResearcherState {}
class ResearcherLoading extends ResearcherState {}

class DatasetsLoaded extends ResearcherState {
  final List<dynamic> datasets;
  const DatasetsLoaded(this.datasets);
  @override
  List<Object?> get props => [datasets];
}

class RequestSubmitted extends ResearcherState {
  final String contractId;
  const RequestSubmitted(this.contractId);
  @override
  List<Object?> get props => [contractId];
}

class DatasetSelected extends ResearcherState {
  final Map<String, dynamic> dataset;
  const DatasetSelected(this.dataset);
  @override
  List<Object?> get props => [dataset];
}

class ResearcherError extends ResearcherState {
  final String message;
  const ResearcherError(this.message);
  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class ResearcherBloc extends Bloc<ResearcherEvent, ResearcherState> {
  final ApiClient _api;

  ResearcherBloc(this._api) : super(ResearcherInitial()) {
    on<SearchDatasets>(_onSearch);
    on<SubmitRequest>(_onSubmit);
    on<SelectDataset>(_onSelectDataset);
  }

  Future<void> _onSearch(SearchDatasets event, Emitter<ResearcherState> emit) async {
    emit(ResearcherLoading());
    try {
      final datasets = await _api.searchDatasets(
        category: event.category,
        dataType: event.dataType,
      );
      emit(DatasetsLoaded(datasets));
    } catch (e) {
      emit(ResearcherError(e.toString()));
    }
  }

  Future<void> _onSubmit(SubmitRequest event, Emitter<ResearcherState> emit) async {
    emit(ResearcherLoading());
    try {
      final result = await _api.submitComputationRequest(event.payload);
      emit(RequestSubmitted(result['contractId'] as String? ?? ''));
    } catch (e) {
      emit(ResearcherError(e.toString()));
    }
  }

  Future<void> _onSelectDataset(SelectDataset event, Emitter<ResearcherState> emit) async {
    emit(DatasetSelected(event.dataset));
  }
}
