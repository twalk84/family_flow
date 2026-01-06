// FILE: lib/assistant_client.dart
//
// Minimal, audited HTTP client for the AI assistant.
// - Uses ASSISTANT_BASE_URL from dart-define (validated by lib/config/env.dart)
// - Sends Firebase ID token when provided (Authorization: Bearer ...)
// - Tries POST /assistant/chat first, falls back to POST /assistant if 404
// - Parses common response shapes (reply/text + action/actions)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config/env.dart';

class AssistantClient {
  AssistantClient({
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 20);

  final http.Client _client;
  final Duration _timeout;

  Uri _uri(String path) {
    final base = assistantBaseUri();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return base.resolve(normalizedPath);
  }

  Future<AssistantResponse> chat({
    required String text,
    required String familyId,
    required String userId,
    String? userEmail,
    String? idToken, // ✅ optional, but pass it from FirebaseAuth
  }) async {
    final t = text.trim();
    if (t.isEmpty) {
      return const AssistantResponse(reply: 'Please type something first.', action: null);
    }

    final payload = <String, dynamic>{
      // include both keys to maximize server compatibility
      'text': t,
      'message': t,
      'familyId': familyId,
      'userId': userId,
      if (userEmail != null) 'userEmail': userEmail,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = idToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    // Prefer /assistant/chat, fallback to /assistant if needed
    final endpoints = <String>['/assistant/chat', '/assistant'];

    http.Response? lastRes;

    for (final ep in endpoints) {
      try {
        final res = await _client
            .post(
              _uri(ep),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(_timeout);

        lastRes = res;

        if (res.statusCode == 404) {
          // Try fallback endpoint
          continue;
        }

        if (res.statusCode < 200 || res.statusCode >= 300) {
          final body = _clip(res.body);
          return AssistantResponse(
            reply: 'Assistant error (${res.statusCode}). $body',
            action: null,
          );
        }

        return _parse(res.body);
      } on TimeoutException {
        return const AssistantResponse(
          reply: 'Assistant timed out. Please try again.',
          action: null,
        );
      } catch (e) {
        // If fallback exists, continue; else return error
        if (ep != endpoints.last) continue;
        return AssistantResponse(
          reply: 'Could not reach assistant service: $e',
          action: null,
        );
      }
    }

    // Both endpoints 404 or otherwise failed
    final status = lastRes?.statusCode;
    return AssistantResponse(
      reply: 'Assistant endpoint not found${status == null ? '' : ' (HTTP $status)'} at configured base URL.',
      action: null,
    );
  }

  AssistantResponse _parse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const AssistantResponse(reply: '(empty response)', action: null);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      // Non-JSON response (treat as text reply)
      return AssistantResponse(reply: trimmed, action: null);
    }

    if (decoded is! Map<String, dynamic>) {
      return const AssistantResponse(reply: 'Assistant returned invalid response format.', action: null);
    }

    final reply = (decoded['reply'] ?? decoded['text'] ?? '').toString().trim();

    // Support either 'action' or 'actions'
    dynamic action = decoded['action'];
    final actions = decoded['actions'];
    if (action == null && actions is List) {
      action = actions; // AssistantSheet will iterate this list
    }

    return AssistantResponse(
      reply: reply.isEmpty ? '(no reply)' : reply,
      action: action,
    );
  }

  String _clip(String s) {
    final t = s.trim();
    if (t.length <= 400) return t;
    return '${t.substring(0, 400)}...';
  }

  void dispose() => _client.close();
}

class AssistantResponse {
  final String reply;
  final dynamic action;

  const AssistantResponse({
    required this.reply,
    required this.action,
  });
}
