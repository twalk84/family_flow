import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:life_os/config/env.dart';

class AssistantApi {
  final http.Client _client;
  AssistantApi({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> chat(Map<String, dynamic> payload) async {
    final url = assistantBaseUri().resolve('/assistant/chat');

    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Assistant error ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
