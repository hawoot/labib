/// Public file-picker API. Resolves to the web implementation when compiling
/// for web, and to a stub on native builds (Android/iOS) — where `dart:js_interop`
/// and `package:web` don't exist. Native file picking can be added later with a
/// platform plugin behind this same API.
export 'picked_file.dart';
export 'web_file_picker.dart' if (dart.library.io) 'file_picker_stub.dart';
