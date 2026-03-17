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

/// Register a brand-new patient account (generates DID + wallet on the API).
class RegisterPatient extends AuthEvent {}

/// Register a brand-new researcher account.
class RegisterResearcher extends AuthEvent {
  final String? organisation;
  const RegisterResearcher({this.organisation});
  @override
  List<Object?> get props => [organisation];
}

/// Login with an existing DID.
class LoginWithDID extends AuthEvent {
  final String did;
  final UserRole role;
  const LoginWithDID(this.did, this.role);
  @override
  List<Object?> get props => [did, role];
}

/// Quick role select (dev / demo — skips server round-trip).
class SelectRole extends AuthEvent {
  final UserRole role;
  final String did;
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

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserRole role;
  final String did;
  final String? walletAddress;
  const AuthAuthenticated(this.role, this.did, {this.walletAddress});
  @override
  List<Object?> get props => [role, did, walletAddress];
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiClient _api;

  AuthBloc(this._api) : super(AuthInitial()) {
    on<RegisterPatient>(_onRegister);
    on<RegisterResearcher>(_onRegisterResearcher);
    on<LoginWithDID>(_onLogin);
    on<SelectRole>(_onSelectRole);
    on<SignOut>(_onSignOut);
  }

  Future<void> _onRegister(RegisterPatient event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _api.registerPatient();
      final token = data['token'] as String?;
      if (token != null) _api.setAuthToken(token);
      emit(AuthAuthenticated(
        UserRole.patient,
        data['did'] as String,
        walletAddress: data['walletAddress'] as String?,
      ));
    } catch (e) {
      emit(AuthError('Registration failed: $e'));
    }
  }

  Future<void> _onRegisterResearcher(RegisterResearcher event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _api.registerResearcher(organisation: event.organisation);
      final token = data['token'] as String?;
      if (token != null) _api.setAuthToken(token);
      emit(AuthAuthenticated(
        UserRole.researcher,
        data['did'] as String,
        walletAddress: data['walletAddress'] as String?,
      ));
    } catch (e) {
      emit(AuthError('Registration failed: $e'));
    }
  }

  Future<void> _onLogin(LoginWithDID event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _api.login(event.did, event.role.name);
      final token = data['token'] as String?;
      if (token != null) _api.setAuthToken(token);
      emit(AuthAuthenticated(event.role, event.did));
    } catch (e) {
      emit(AuthError('Login failed: $e'));
    }
  }

  void _onSelectRole(SelectRole event, Emitter<AuthState> emit) {
    // Demo / offline path — no server call
    emit(AuthAuthenticated(event.role, event.did));
  }

  void _onSignOut(SignOut event, Emitter<AuthState> emit) {
    _api.clearAuthToken();
    emit(AuthInitial());
  }
}
