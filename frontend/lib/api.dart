import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thin client over the labib backend.
///
/// The web app is served from the SAME host as the API, so we derive the API
/// origin from the page URL — which means it keeps working even if the VPS
/// tunnel URL changes, and there's no CORS to configure.
class Api {
  static final String base = Uri.base.origin;
  static String? _userId;

  static Future<void> ensureUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    if (_userId != null) return;
    final res = await http.post(Uri.parse('$base/auth/anonymous'));
    _userId = (jsonDecode(res.body) as Map)['user_id'] as String;
    await prefs.setString('user_id', _userId!);
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_userId != null) 'X-User-Id': _userId!,
      };

  static Future<List<dynamic>> listJourneys() async {
    final res = await http.get(Uri.parse('$base/journeys'), headers: _headers);
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createJourney(
      String title, String intent) async {
    final res = await http.post(Uri.parse('$base/journeys'),
        headers: _headers,
        body: jsonEncode({'title': title, 'intent': intent}));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> listDocuments(String jid) async {
    final res = await http.get(Uri.parse('$base/journeys/$jid/documents'),
        headers: _headers);
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<void> addText(String jid, String title, String text) async {
    await http.post(Uri.parse('$base/journeys/$jid/documents/text'),
        headers: _headers,
        body: jsonEncode({'title': title, 'text': text}));
  }

  static Future<void> addFile(
      String jid, String filename, List<int> bytes) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$base/journeys/$jid/documents/file'));
    if (_userId != null) req.headers['X-User-Id'] = _userId!;
    req.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final res = await req.send();
    if (res.statusCode >= 400) {
      throw Exception('Upload failed (HTTP ${res.statusCode})');
    }
  }

  static Future<void> startIngest(String jid) async {
    await http.post(Uri.parse('$base/journeys/$jid/ingest'), headers: _headers);
  }

  /// Latest crunch job, or null if none has run yet (404).
  static Future<Map<String, dynamic>?> getIngest(String jid) async {
    final res =
        await http.get(Uri.parse('$base/journeys/$jid/ingest'), headers: _headers);
    if (res.statusCode == 404) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getCurriculum(String jid) async {
    final res = await http.get(Uri.parse('$base/journeys/$jid/curriculum'),
        headers: _headers);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
