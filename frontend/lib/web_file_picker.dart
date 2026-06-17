import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// Opens the browser's native file dialog and returns the chosen file's bytes.
///
/// Web-only (we currently build for web). When we package the Android app we'll
/// add a mobile implementation behind the same `pickFile` signature.
Future<PickedFile?> pickFile({String accept = '.pdf,.txt,.md'}) {
  final completer = Completer<PickedFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept;
  input.style.display = 'none';
  web.document.body!.appendChild(input);

  void finish(PickedFile? value) {
    input.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final buffer = reader.result as JSArrayBuffer;
      finish(PickedFile(file.name, buffer.toDart.asUint8List()));
    }.toJS;
    reader.onerror = (web.Event _) {
      finish(null);
    }.toJS;
    reader.readAsArrayBuffer(file);
  }.toJS;

  // If the user cancels, no event fires; that's fine — the future just never
  // completes for that attempt, and the next tap creates a fresh input.
  input.click();
  return completer.future;
}

/// Like [pickFile], but lets the user choose several files at once. Returns
/// them all (empty list if the dialog is dismissed with nothing selected).
Future<List<PickedFile>> pickFiles({String accept = '.pdf,.txt,.md'}) {
  final completer = Completer<List<PickedFile>>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept;
  input.multiple = true;
  input.setAttribute('multiple', 'multiple'); // belt-and-suspenders for the dialog
  input.style.display = 'none';
  web.document.body!.appendChild(input);

  void finish(List<PickedFile> value) {
    input.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(const []);
      return;
    }
    final reads = <Future<PickedFile>>[
      for (var i = 0; i < files.length; i++) _readFile(files.item(i)!),
    ];
    Future.wait(reads).then(finish).catchError((Object _) {
      finish(const <PickedFile>[]);
    });
  }.toJS;

  input.click();
  return completer.future;
}

Future<PickedFile> _readFile(web.File file) {
  final completer = Completer<PickedFile>();
  final reader = web.FileReader();
  reader.onload = (web.Event _) {
    final buffer = reader.result as JSArrayBuffer;
    completer.complete(PickedFile(file.name, buffer.toDart.asUint8List()));
  }.toJS;
  reader.onerror = (web.Event _) {
    completer.completeError(Exception('Could not read ${file.name}'));
  }.toJS;
  reader.readAsArrayBuffer(file);
  return completer.future;
}
