/// Environment configuration.
/// Pass --dart-define=API_URL=https://your-api.com when building for production.
class Env {
  static const String apiUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');
}
