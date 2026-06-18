/// Where the native app (Android/iOS) finds the backend.
///
/// This is the single, version-controlled source of truth for the server URL.
/// To point the app at a different server: change this line, commit, rebuild.
/// The change is then traceable in git history.
///
/// The WEB app ignores this — it's served *by* the backend, so it always talks
/// to the same origin it was loaded from (and follows the URL automatically,
/// even if the tunnel changes). That's why the web app has nothing to configure.
const String kServerUrl =
    'https://exposed-port-8000-7173e73f3a75602b4842-3upcvdxuqf.h65.openclaw.agent37.com';
