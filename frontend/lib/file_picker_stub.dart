import 'picked_file.dart';

/// Native placeholder. The current pickers are web-only (they use the browser's
/// file dialog); on a native build, adding files isn't wired up yet. Pasting
/// text still works. Hooking up a native picker (e.g. the `file_picker` plugin)
/// behind this same API is a later step.
Future<PickedFile?> pickFile({String accept = '.pdf,.txt,.md'}) async {
  throw UnsupportedError('Adding files is only available on the web app today.');
}

Future<List<PickedFile>> pickFiles({String accept = '.pdf,.txt,.md'}) async {
  throw UnsupportedError('Adding files is only available on the web app today.');
}
