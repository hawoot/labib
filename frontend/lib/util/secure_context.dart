/// Whether the page is a "secure context" (HTTPS or localhost). Browsers block
/// the microphone and camera on insecure (http://) origins, which is the usual
/// reason voice/photo "do nothing" on a deployed web build.
///
/// Resolves to the web implementation on web and a no-op (always true) on
/// native, where the concept doesn't apply.
export 'secure_context_stub.dart'
    if (dart.library.js_interop) 'secure_context_web.dart';
