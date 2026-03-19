import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/api_client.dart';
import '../../../core/secure_storage.dart';
import '../../../core/google_auth_service.dart';

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

/// Attempt to restore a previously saved session from secure storage.
class RestoreSession extends AuthEvent {}

/// Register or login via Google — email and name come from the Google account.
class GoogleSignInEvent extends AuthEvent {
  final UserRole role;
  final String? organisation;
  const GoogleSignInEvent({required this.role, this.organisation});
  @override
  List<Object?> get props => [role, organisation];
}

/// Register a brand-new patient account (generates DID + wallet on the API).
class RegisterPatient extends AuthEvent {
  final String name;
  final String email;
  const RegisterPatient({required this.name, required this.email});
  @override
  List<Object?> get props => [name, email];
}

/// Register a brand-new researcher account.
class RegisterResearcher extends AuthEvent {
  final String name;
  final String email;
  final String? organisation;
  const RegisterResearcher({required this.name, required this.email, this.organisation});
  @override
  List<Object?> get props => [name, email, organisation];
}

/// Login with an existing DID.
class LoginWithDID extends AuthEvent {
  final String did;
  final UserRole role;
  const LoginWithDID(this.did, this.role);
  @override
  List<Object?> get props => [did, role];
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
  final String? name;
  final String? email;
  const AuthAuthenticated(this.role, this.did, {this.walletAddress, this.name, this.email});
  @override
  List<Object?> get props => [role, did, walletAddress, name, email];
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
  final GoogleAuthService _googleAuth = GoogleAuthService();

  AuthBloc(this._api) : super(AuthInitial()) {
    on<RestoreSession>(_onRestoreSession);
    on<GoogleSignInEvent>(_onGoogleSignIn);
    on<RegisterPatient>(_onRegister);
    on<RegisterResearcher>(_onRegisterResearcher);
    on<LoginWithDID>(_onLogin);
    on<SignOut>(_onSignOut);
  }

  Future<void> _onRestoreSession(RestoreSession event, Emitter<AuthState> emit) async {
    final identity = await _api.storage.loadIdentity();
    if (identity == null) return;
    emit(AuthLoading());
    try {
      final accounts = await _api.storage.loadAccounts();
      final account = accounts.firstWhere((a) => a.did == identity.did,
          orElse: () => SavedAccount(did: identity.did, role: identity.role));
      final data = await _api.login(identity.did, identity.role);
      final token = data['token'] as String;
      _api.setAuthToken(token);
      await _api.storage.saveToken(token);
      final role = identity.role == 'researcher' ? UserRole.researcher : UserRole.patient;
      emit(AuthAuthenticated(role, identity.did,
          name: account.name, email: account.email));
    } catch (e) {
      emit(AuthInitial());
    }
  }

  Future<void> _onGoogleSignIn(GoogleSignInEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      debugPrint('[GoogleSignIn] Starting sign-in flow, role=${event.role.name}');
      final google = await _googleAuth.signIn();
      if (google == null) {
        debugPrint('[GoogleSignIn] User cancelled');
        emit(AuthInitial()); return;
      }
      debugPrint('[GoogleSignIn] Got Google account: email=${google.email}, name=${google.displayName}');

      final accounts = await _api.storage.loadAccounts();
      debugPrint('[GoogleSignIn] Saved accounts on device: ${accounts.map((a) => a.email).toList()}');
      final existing = accounts.where((a) => a.email == google.email).toList();

      if (existing.isNotEmpty) {
        debugPrint('[GoogleSignIn] Existing account found, logging in DID=${existing.first.did}');
        final account = existing.first;
        final data = await _api.login(account.did, account.role);
        debugPrint('[GoogleSignIn] Login response: $data');
        final token = data['token'] as String;
        _api.setAuthToken(token);
        await _api.storage.saveToken(token);
        final role = account.role == 'researcher' ? UserRole.researcher : UserRole.patient;
        emit(AuthAuthenticated(role, account.did,
            name: account.name, email: account.email));
      } else {
        debugPrint('[GoogleSignIn] New account, registering as ${event.role.name}');
        final Map<String, dynamic> data;
        if (event.role == UserRole.researcher) {
          data = await _api.registerResearcher(organisation: event.organisation);
        } else {
          data = await _api.registerPatient();
        }
        debugPrint('[GoogleSignIn] Register response: $data');
        final token = data['token'] as String;
        final did = data['did'] as String;
        _api.setAuthToken(token);
        await _api.storage.saveSession(
          did: did, token: token, role: event.role.name,
          name: google.displayName, email: google.email,
          organisation: event.organisation,
          avatarColor: _pickColor(did),
        );
        debugPrint('[GoogleSignIn] Session saved, DID=$did');
        emit(AuthAuthenticated(event.role, did,
            walletAddress: data['walletAddress'] as String?,
            name: google.displayName, email: google.email));
      }
    } catch (e, stack) {
      debugPrint('[GoogleSignIn] ERROR: $e');
      debugPrint('[GoogleSignIn] STACK: $stack');
      emit(AuthError('Google sign-in failed: $e'));
    }
  }

  Future<void> _onRegister(RegisterPatient event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _api.registerPatient();
      final token = data['token'] as String;
      final did = data['did'] as String;
      _api.setAuthToken(token);
      await _api.storage.saveSession(
        did: did, token: token, role: 'patient',
        name: event.name,
        email: event.email,
        avatarColor: _pickColor(did),
      );
      emit(AuthAuthenticated(UserRole.patient, did,
          walletAddress: data['walletAddress'] as String?,
          name: event.name, email: event.email));
    } catch (e) {
      emit(AuthError('Registration failed: $e'));
    }
  }

  Future<void> _onRegisterResearcher(RegisterResearcher event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _api.registerResearcher(organisation: event.organisation);
      final token = data['token'] as String;
      final did = data['did'] as String;
      _api.setAuthToken(token);
      await _api.storage.saveSession(
        did: did, token: token, role: 'researcher',
        organisation: event.organisation,
        name: event.name,
        email: event.email,
        avatarColor: _pickColor(did),
      );
      emit(AuthAuthenticated(UserRole.researcher, did,
          walletAddress: data['walletAddress'] as String?,
          name: event.name, email: event.email));
    } catch (e) {
      emit(AuthError('Registration failed: $e'));
    }
  }

  /// Picks a visually distinct color from the DID hash.
  int _pickColor(String did) {
    const colors = [
      0xFF1A73E8, 0xFF0F9D58, 0xFFDB4437, 0xFFF4B400,
      0xFF9C27B0, 0xFF00ACC1, 0xFFE91E63, 0xFF3F51B5,
    ];
    final hash = did.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  Future<void> _onLogin(LoginWithDID event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final accounts = await _api.storage.loadAccounts();
      final account = accounts.firstWhere((a) => a.did == event.did,
          orElse: () => SavedAccount(did: event.did, role: event.role.name));
      final data = await _api.login(event.did, event.role.name);
      final token = data['token'] as String;
      _api.setAuthToken(token);
      await _api.storage.saveToken(token);
      emit(AuthAuthenticated(event.role, event.did,
          name: account.name, email: account.email));
    } catch (e) {
      emit(AuthError('Login failed: $e'));
    }
  }

  Future<void> _onSignOut(SignOut event, Emitter<AuthState> emit) async {
    _api.clearAuthToken();
    await _api.storage.clearToken(); // keep DID/role so "Welcome back" still shows
    emit(AuthInitial());
  }
}
