class ConfluenceSettings {
  const ConfluenceSettings({
    required this.serverUrl,
    required this.username,
    this.lastSyncAt,
    this.lastError,
  });

  const ConfluenceSettings.empty()
      : serverUrl = '',
        username = '',
        lastSyncAt = null,
        lastError = null;

  final String serverUrl;
  final String username;
  final DateTime? lastSyncAt;
  final String? lastError;

  bool get isConfigured => serverUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// Normalizes a server root and prevents accidentally appending the API path
  /// twice when a user pastes an endpoint from browser developer tools.
  Uri get baseUri {
    var value = serverUrl.trim();
    value = value.replaceFirst(RegExp(r'/rest/api/content/?$'), '');
    if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      value = 'https://$value';
    }
    return Uri.parse(value.endsWith('/') ? value.substring(0, value.length - 1) : value);
  }

  ConfluenceSettings copyWith({
    String? serverUrl,
    String? username,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return ConfluenceSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'serverUrl': serverUrl,
        'username': username,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'lastError': lastError,
      };

  factory ConfluenceSettings.fromJson(Map<String, dynamic> json) {
    final lastSync = json['lastSyncAt'] as String?;
    return ConfluenceSettings(
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      lastSyncAt: lastSync == null ? null : DateTime.tryParse(lastSync),
      lastError: json['lastError'] as String?,
    );
  }
}
