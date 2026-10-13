import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'database_service.dart';
import 'settings_service.dart';
import 'sync_service.dart';

const _dailySyncTask = 'daily-confluence-sync';
const _dailySyncUniqueName = 'daily-confluence-sync-v1';

/// Android invokes this in a separate Dart isolate. It must stay a top-level
/// function and must not depend on UI state.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await DatabaseService.configureForCurrentPlatform();
      final settings = await SettingsService.instance.load();
      if (!settings.isConfigured) {
        return true;
      }
      await SyncService().synchronize();
      return true;
    } catch (_) {
      // Returning false lets WorkManager retry according to Android policy.
      // Credentials and page contents are intentionally never logged here.
      return false;
    }
  });
}

class BackgroundSyncService {
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      return;
    }
    await Workmanager().initialize(backgroundSyncDispatcher, isInDebugMode: false);
  }

  Future<void> updateSchedule() async {
    if (!Platform.isAndroid) {
      return;
    }
    final settings = await SettingsService.instance.load();
    await Workmanager().cancelByUniqueName(_dailySyncUniqueName);
    if (!settings.isConfigured) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      _dailySyncUniqueName,
      _dailySyncTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
