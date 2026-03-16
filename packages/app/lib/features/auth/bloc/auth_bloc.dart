import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/api_client.dart';

// ---------------------------------------------------------------------------
// Role
// ---------------------------------------------------------------------------

enum UserRole { patient, researcher }

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class SelectRole extends AuthEvent {
  final UserRole role;
  final String did; // patient DID or researcher wallet address
  const SelectRole(this.role, this.did);
  @override
  List<Object?> get props => [role, did];
}

class SignOut extends AuthEvent {}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserRole role;
  final String did;
  const AuthAuthenticated(this.role, this.did);
  @override
  List<Object?> get props => [role, did];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  // ignore: unused_field
  final ApiClient _api;

  AuthBloc(this._api) : super(AuthInitial()) {
    on<SelectRole>((event, emit) {
      emit(AuthAuthenticated(event.role, event.did));
    });
    on<SignOut>((event, emit) => emit(AuthInitial()));
  }
}
