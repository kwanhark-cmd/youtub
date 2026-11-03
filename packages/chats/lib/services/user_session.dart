import 'dart:convert';
import 'dart:io';

import '../classify/classification_service.dart';
import '../data/app_database.dart';
import '../data/content_cipher.dart';
import '../data/conversation_store.dart';
import '../data/key_store.dart';
import '../data/topic_store.dart';
import '../models/models.dart';
import '../search/search_service.dart';
import 'settings.dart';

/// 로그인한 사용자 한 명의 자료 묶음.
class UserSession {
  final UserProfile user;
  final Directory dir;
  final AppDatabase database;
  final ConversationStore store;
  final TopicStore topics;
  final SearchService search;
  final ClassificationService classifier;
  AppSettings settings;

  UserSession._(this.user, this.dir, this.database, this.store, this.topics, this.search, this.classifier, this.settings);

  File get settingsFile => File('${dir.path}/settings.json');

  static String dataKeyName(String userId) => 'datakey-$userId';
  static String apiKeyName(String userId) => 'apikey-claude-$userId';

  static Future<UserSession> open(UserProfile user, Directory dir, KeyStore keys, {bool inMemory = false}) async {
    dir.createSync(recursive: true);
    var keyB64 = await keys.read(dataKeyName(user.id));
    if (keyB64 == null) {
      keyB64 = base64.encode(ContentCipher.newKeyBytes());
      await keys.write(dataKeyName(user.id), keyB64);
    }
    final cipher = ContentCipher(base64.decode(keyB64));
    final db = inMemory ? AppDatabase.openInMemory() : AppDatabase.openFile('${dir.path}/data.db');
    final store = ConversationStore(db, cipher);
    final topics = TopicStore(db.db);
    final settings = AppSettings.load(File('${dir.path}/settings.json'));
    return UserSession._(user, dir, db, store, topics, SearchService(store), ClassificationService(store, topics), settings);
  }

  void saveSettings() => settings.save(settingsFile);

  void close() => database.close();
}
