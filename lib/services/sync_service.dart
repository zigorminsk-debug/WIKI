import 'dart:math';

import '../models/confluence_settings.dart';
import '../models/sync_result.dart';
import 'confluence_client.dart';
import 'database_service.dart';
import 'settings_service.dart';

class SyncService {
  SyncService({
    ConfluenceClient? client,
    SettingsService? settingsService,
    DatabaseService? databaseService,
  })  : _client = client ?? ConfluenceClient(),
        _settingsService = settingsService ?? SettingsService.instance,
        _databaseService = databaseService ?? DatabaseService.instance;

  final ConfluenceClient _client;
  final SettingsService _settingsService;
  final DatabaseService _databaseService;

  Future<SyncResult> synchronize() async {
    final settings = await _settingsService.load();
    final password = await _settingsService.loadPassword();
    final now = DateTime.now();
    final syncRun = '${now.microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

    try {
      final pages = await _client.fetchAllPages(settings: settings, password: password, syncRun: syncRun);
      await _databaseService.replaceAllPages(pages, syncRun);
      await _settingsService.save(settings.copyWith(lastSyncAt: now, clearLastError: true));
      return SyncResult(pageCount: pages.length, completedAt: now);
    } on ConfluenceException catch (error) {
      await _settingsService.save(settings.copyWith(lastError: error.message));
      rethrow;
    } catch (_) {
      const message = 'Не удалось синхронизировать. Проверьте сеть, адрес сервера и сертификат HTTPS.';
      await _settingsService.save(settings.copyWith(lastError: message));
      throw const ConfluenceException(message);
    }
  }
}
