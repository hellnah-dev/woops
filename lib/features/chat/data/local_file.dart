import 'dart:io';
import 'dart:typed_data';

/// Reads a photo saved on this phone (kept separate so tests can avoid disk).
Future<Uint8List> readLocalFile(String path) => File(path).readAsBytes();
