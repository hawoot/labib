import 'dart:typed_data';

/// A file the user chose, with its bytes in memory. Platform-agnostic so both
/// the web and native (stub) pickers can share it.
class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
