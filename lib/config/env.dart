// FILE: lib/config/env.dart
//
// Central place for build-time env values (dart-define).

const String kAssistantBaseUrlRaw =
    String.fromEnvironment('ASSISTANT_BASE_URL', defaultValue: '');

final String kAssistantBaseUrl = kAssistantBaseUrlRaw.trim();

final bool kAssistantConfigured = kAssistantBaseUrl.isNotEmpty;

class AssistantNotConfiguredException implements Exception {
  const AssistantNotConfiguredException();

  @override
  String toString() =>
      'Assistant is not configured yet. Set ASSISTANT_BASE_URL at build time.';
}

/// Returns the assistant base URL as a validated Uri.
/// Throws if missing or invalid so we never silently fall back.
Uri assistantBaseUri() {
  if (!kAssistantConfigured) {
    throw const AssistantNotConfiguredException();
  }

  final uri = Uri.parse(kAssistantBaseUrl);

  final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
  final hasHost = uri.host.isNotEmpty;

  if (!isHttp || !hasHost) {
    throw FormatException(
      'ASSISTANT_BASE_URL must be a full http(s) URL, e.g. '
      '"https://...run.app" (got: "$kAssistantBaseUrl")',
    );
  }

  return uri;
}
