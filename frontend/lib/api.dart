import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Raised for any non-2xx API response, carrying the server's `detail` message.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

/// Thin client over the labib backend.
///
/// The web app is served from the SAME host as the API, so we derive the API
/// origin from the page URL — which means it keeps working even if the VPS
/// tunnel URL changes, and there's no CORS to configure.
///
/// Auth is centralized: every request carries the stored `X-User-Id`, and any
/// 401 (e.g. the stored id no longer exists after a DB reset) transparently
/// re-authenticates once and retries — so a stale id self-heals instead of
/// crashing the app.
class Api {
  /// API origin.
  /// - **Web**: the page origin (served from the backend, so always correct;
  ///   follows the tunnel automatically — nothing to configure).
  /// - **Native (Android/iOS)**: there's no page URL, so it uses the
  ///   version-controlled [kServerUrl] baked in at build time. Change that
  ///   constant + rebuild to point at a different server.
  static final String base = kIsWeb ? Uri.base.origin : kServerUrl;

  static String? _userId;
  static String? _code;

  /// The current account's login code (shown to the user so they can get back
  /// in on another device). Null until [ensureUser] has run.
  static String? get code => _code;

  static Future<void> ensureUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    _code = prefs.getString('code');
    if (_userId != null) return; // validity is checked lazily on first 401
    await _reauth();
  }

  /// Whether this device already has an account, without creating one. Lets the
  /// app show the landing screen to first-time visitors and skip straight to
  /// their journeys for returning ones.
  static Future<bool> hasAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') != null;
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
      throw ApiException(res.statusCode, 'Login failed (HTTP ${res.statusCode})');
    }
    final prefs = await SharedPreferences.getInstance();
    await _store(prefs, jsonDecode(res.body) as Map<String, dynamic>);
    return true;
  }

  // --- Plumbing ------------------------------------------------------------

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_userId != null) 'X-User-Id': _userId!,
      };

  /// Drop the stored identity and mint a fresh anonymous account.
  static Future<void> _reauth() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = null;
    _code = null;
    await prefs.remove('user_id');
    await prefs.remove('code');
    final res = await http.post(Uri.parse('$base/auth/anonymous'));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Could not start a session.');
    }
    await _store(prefs, jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> _store(
      SharedPreferences prefs, Map<String, dynamic> data) async {
    _userId = data['user_id'] as String;
    _code = data['code'] as String?;
    await prefs.setString('user_id', _userId!);
    if (_code != null) await prefs.setString('code', _code!);
  }

  /// Run [build] (which uses the current [_headers]); on a 401, re-auth once
  /// and run it again so a stale id heals itself.
  static Future<http.Response> _send(
      Future<http.Response> Function() build) async {
    var res = await build();
    if (res.statusCode == 401) {
      await _reauth();
      res = await build();
    }
    return res;
  }

  static Future<http.Response> _get(String path) =>
      _send(() => http.get(Uri.parse('$base$path'), headers: _headers));

  static Future<http.Response> _post(String path, [Object? body]) => _send(
      () => http.post(Uri.parse('$base$path'),
          headers: _headers, body: body == null ? null : jsonEncode(body)));

  static String _detail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) return '${body['detail']}';
    } catch (_) {/* non-JSON body */}
    return 'HTTP ${res.statusCode}';
  }

  static dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) throw ApiException(res.statusCode, _detail(res));
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  static Map<String, dynamic> _asMap(http.Response res) {
    final data = _decode(res);
    if (data is Map<String, dynamic>) return data;
    throw ApiException(res.statusCode, 'Unexpected response from server.');
  }

  static List<dynamic> _asList(http.Response res) {
    final data = _decode(res);
    if (data is List) return data;
    throw ApiException(res.statusCode, 'Unexpected response from server.');
  }

  // --- Journeys ------------------------------------------------------------

  static Future<List<dynamic>> listJourneys({bool archived = false}) async =>
      _asList(await _get('/journeys${archived ? '?archived=true' : ''}'));

  static Future<Map<String, dynamic>> createJourney(
          String title, String intent) async =>
      _asMap(await _post('/journeys', {'title': title, 'intent': intent}));

  static Future<void> archiveJourney(String jid) async =>
      _decode(await _post('/journeys/$jid/archive'));

  static Future<void> unarchiveJourney(String jid) async =>
      _decode(await _post('/journeys/$jid/unarchive'));

  static Future<void> deleteJourney(String jid) async => _decode(
      await _send(() => http.delete(Uri.parse('$base/journeys/$jid'),
          headers: _headers)));

  // --- Documents -----------------------------------------------------------

  static Future<List<dynamic>> listDocuments(String jid) async =>
      _asList(await _get('/journeys/$jid/documents'));

  static Future<void> addText(String jid, String title, String text) async =>
      _decode(await _post(
          '/journeys/$jid/documents/text', {'title': title, 'text': text}));

  static Future<void> addFile(
      String jid, String filename, List<int> bytes) async {
    Future<http.StreamedResponse> run() {
      final req = http.MultipartRequest(
          'POST', Uri.parse('$base/journeys/$jid/documents/file'));
      if (_userId != null) req.headers['X-User-Id'] = _userId!;
      req.files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      return req.send();
    }

    var res = await run();
    if (res.statusCode == 401) {
      await _reauth();
      res = await run();
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Upload of "$filename" failed '
          '(HTTP ${res.statusCode})');
    }
  }

  // --- Crunch / curriculum -------------------------------------------------

  static Future<void> startIngest(String jid) async =>
      _decode(await _post('/journeys/$jid/ingest'));

  /// Latest crunch job, or null if none has run yet (404).
  static Future<Map<String, dynamic>?> getIngest(String jid) async {
    final res = await _get('/journeys/$jid/ingest');
    if (res.statusCode == 404) return null;
    return _asMap(res);
  }

  static Future<Map<String, dynamic>> getCurriculum(String jid) async =>
      _asMap(await _get('/journeys/$jid/curriculum'));

  // --- Drilling ------------------------------------------------------------

  static Future<List<dynamic>> getSession(String jid) async =>
      _asMap(await _get('/journeys/$jid/session'))['items'] as List<dynamic>;

  static Future<Map<String, dynamic>> submitAttempt(
          String jid, String questionId, String answer) async =>
      _asMap(await _post(
          '/journeys/$jid/attempts', {'question_id': questionId, 'answer': answer}));

  static Future<Map<String, dynamic>> getProgress(String jid) async =>
      _asMap(await _get('/journeys/$jid/progress'));
}
