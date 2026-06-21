/// Public file-picker API. Resolves to the browser file dialog when compiling
/// for web, and to the native `file_picker` plugin on Android/iOS — both behind
/// the same `pickFile` / `pickFiles` signatures (web uses `dart:js_interop` /
/// `package:web`, which don't exist natively, hence the conditional export).
export 'picked_file.dart';
export 'web_file_picker.dart' if (dart.library.io) 'file_picker_native.dart';
