/// Build-time configuration. Override with
/// `flutter run -d chrome --dart-define=API_URL=https://sandbox.badrgo.com`.
class AppConfig {
  const AppConfig({required this.apiUrl});

  factory AppConfig.fromEnvironment() {
    const url = String.fromEnvironment(
      'API_URL',
      defaultValue: 'https://sandbox.badrgo.com',
    );
    return AppConfig(apiUrl: url.endsWith('/') ? url.substring(0, url.length - 1) : url);
  }

  final String apiUrl;

  Uri get apiUri => Uri.parse(apiUrl);

  /// `http(s)://host` becomes `ws(s)://host/ws`.
  Uri webSocketUri(String token) {
    final base = apiUri;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/ws',
      queryParameters: {'token': token},
    );
  }
}
