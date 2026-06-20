/// Native: there's no browser security context — mic/camera permissions are
/// handled by the OS, so treat it as secure.
bool isPageSecure() => true;
