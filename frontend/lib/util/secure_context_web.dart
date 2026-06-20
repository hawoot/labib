import 'package:web/web.dart' as web;

/// Web: true on HTTPS or localhost; false on a plain http:// origin (where
/// browsers block getUserMedia / SpeechRecognition).
bool isPageSecure() => web.window.isSecureContext;
