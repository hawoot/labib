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
  static String? _code;

  /// The current account's login code (shown to the user so they can get back
  /// in on another device). Null until [ensureUser] has run.
  static String? get code => _code;

  static Future<void> ensureUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    _code = prefs.getString('code');
    if (_userId != null) return;
    final res = await http.post(Uri.parse('$base/auth/anonymous'));
    await _store(prefs, jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Switch to the account identified by [code]. Returns false if no such
  /// account exists; throws on other failures.
  static Future<bool> loginWithCode(String code) async {
    final res = await http.post(
      Uri.parse('$base/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    if (res.statusCode == 404) return false;
    if (res.statusCode >= 400) {
      throw Exception('Login failed (HTTP ${res.statusCode})');
    }
    final prefs = await SharedPreferences.getInstance();
    await _store(prefs, jsonDecode(res.body) as Map<String, dynamic>);
    return true;
  }

  static Future<void> _store(
      SharedPreferences prefs, Map<String, dynamic> data) async {
    _userId = data['user_id'] as String;
    _code = data['code'] as String?;
    await prefs.setString('user_id', _userId!);
    if (_code != null) await prefs.setString('code', _code!);
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

  // --- Drilling ---
  static Future<List<dynamic>> getSession(String jid) async {
    final res = await http.get(Uri.parse('$base/journeys/$jid/session'),
        headers: _headers);
    return (jsonDecode(res.body) as Map<String, dynamic>)['items']
        as List<dynamic>;
  }

  static Future<Map<String, dynamic>> submitAttempt(
      String jid, String questionId, String answer) async {
    final res = await http.post(Uri.parse('$base/journeys/$jid/attempts'),
        headers: _headers,
        body: jsonEncode({'question_id': questionId, 'answer': answer}));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getProgress(String jid) async {
    final res = await http.get(Uri.parse('$base/journeys/$jid/progress'),
        headers: _headers);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
