import 'package:file_picker/file_picker.dart' as fp;

import 'picked_file.dart';

/// Native (Android/iOS) file picking via the `file_picker` plugin. Mirrors the
/// web picker's API so callers don't care which platform they're on. Bytes are
/// loaded into memory (`withData: true`) to match the upload path, which sends
/// raw bytes.
List<String> _extensions(String accept) => [
      for (final part in accept.split(','))
        if (part.trim().replaceFirst('.', '').isNotEmpty)
          part.trim().replaceFirst('.', '').toLowerCase(),
    ];

Future<PickedFile?> pickFile({String accept = '.pdf,.txt,.md'}) async {
  final res = await fp.FilePicker.platform.pickFiles(
    type: fp.FileType.custom,
    allowedExtensions: _extensions(accept),
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  if (f.bytes == null) return null;
  return PickedFile(f.name, f.bytes!);
}

Future<List<PickedFile>> pickFiles({String accept = '.pdf,.txt,.md'}) async {
  final res = await fp.FilePicker.platform.pickFiles(
    type: fp.FileType.custom,
    allowedExtensions: _extensions(accept),
    withData: true,
    allowMultiple: true,
  );
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.bytes != null) PickedFile(f.name, f.bytes!),
  ];
}
