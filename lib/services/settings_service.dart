import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/confluence_settings.dart';

class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();
  static const _settingsKey = 'confluence_settings_v1';
  static const _passwordKey = 'confluence_password_v1';
  static const _secureStorage = FlutterSecureStorage();

  Future<ConfluenceSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_settingsKey);
    if (raw == null) {
      return const ConfluenceSettings.empty();
    }
    try {
      return ConfluenceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const ConfluenceSettings.empty();
    }
  }

  Future<String> loadPassword() => _secureStorage.read(key: _passwordKey).then((value) => value ?? '');

  Future<void> save(ConfluenceSettings settings, {String? password}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
    if (password != null) {
      await _secureStorage.write(key: _passwordKey, value: password);
    }
  }

  Future<void> clearPassword() => _secureStorage.delete(key: _passwordKey);
}
