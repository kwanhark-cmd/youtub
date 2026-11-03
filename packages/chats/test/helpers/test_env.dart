import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_organizer/data/app_database.dart';
import 'package:ai_chat_organizer/data/content_cipher.dart';
import 'package:ai_chat_organizer/data/conversation_store.dart';
import 'package:ai_chat_organizer/parsers/import_reader.dart';

Uint8List sampleBytes(String name) => File('assets/samples/$name').readAsBytesSync();

ConversationStore memoryStore() => ConversationStore(AppDatabase.openInMemory(), ContentCipher(ContentCipher.newKeyBytes()));

Future<ConversationStore> storeWithSamples() async {
  final s = memoryStore();
  for (final f in ['claude_sample.json', 'chatgpt_sample.json', 'gemini_sample.html']) {
    await s.importResults(ImportReader.read(f, sampleBytes(f)), fileName: f);
  }
  return s;
}
