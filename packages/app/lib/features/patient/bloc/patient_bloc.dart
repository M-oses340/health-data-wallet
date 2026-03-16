import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/api_client.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class PatientEvent extends Equatable {
  const PatientEvent();
  @override
  List<Object?> get props => [];
}

class LoadPatientData extends PatientEvent {
  final String did;
  const LoadPatientData(this.did);
  @override
  List<Object?> get props => [did];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class PatientState extends Equatable {
  const PatientState();
  @override
  List<Object?> get props => [];
}

class PatientInitial extends PatientState {}
class PatientLoading extends PatientState {}

class PatientLoaded extends PatientState {
  final List<dynamic> payments;
  final List<dynamic> auditTrail;
  const PatientLoaded({required this.payments, required this.auditTrail});
  @override
  List<Object?> get props => [payments, auditTrail];
}

class PatientError extends PatientState {
  final String message;
  const PatientError(this.message);
  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class PatientBloc extends Bloc<PatientEvent, PatientState> {
  final ApiClient _api;

  PatientBloc(this._api) : super(PatientInitial()) {
    on<LoadPatientData>(_onLoad);
  }

  Future<void> _onLoad(LoadPatientData event, Emitter<PatientState> emit) async {
    emit(PatientLoading());
    try {
      final payments = await _api.getPayments(event.did);
      final audit = await _api.getAuditTrail(event.did);
      emit(PatientLoaded(
        payments: (payments['payments'] as List?) ?? [],
        auditTrail: (audit['entries'] as List?) ?? [],
      ));
    } catch (e) {
      emit(PatientError(e.toString()));
    }
  }
}