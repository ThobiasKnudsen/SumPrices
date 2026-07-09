class AppConfig {
  /// Backend base URL. Override at build/run time with
  /// `--dart-define=API_BASE=https://your.host`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3000',
  );
}
