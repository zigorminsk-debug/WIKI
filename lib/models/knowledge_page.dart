class KnowledgePage {
  const KnowledgePage({
    required this.id,
    required this.title,
    required this.spaceKey,
    required this.bodyHtml,
    required this.version,
    required this.updatedAt,
    required this.path,
    required this.webUrl,
    required this.syncRun,
  });

  final String id;
  final String title;
  final String spaceKey;
  final String bodyHtml;
  final int version;
  final DateTime? updatedAt;
  final String path;
  final String webUrl;
  final String syncRun;

  /// Parses the shape returned by Confluence REST API with
  /// `expand=body.storage,version,space,ancestors`.
  factory KnowledgePage.fromConfluence(Map<String, dynamic> json, {required String syncRun, required Uri baseUri}) {
    final body = (json['body'] as Map<String, dynamic>?)?['storage'] as Map<String, dynamic>?;
    final version = json['version'] as Map<String, dynamic>?;
    final space = json['space'] as Map<String, dynamic>?;
    final links = json['_links'] as Map<String, dynamic>?;
    final ancestors = (json['ancestors'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((ancestor) => ancestor['title'] as String? ?? '')
        .where((title) => title.isNotEmpty)
        .toList();
    final webUi = links?['webui'] as String? ?? '';

    return KnowledgePage(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Без названия',
      spaceKey: space?['key'] as String? ?? '',
      bodyHtml: body?['value'] as String? ?? '',
      version: (version?['number'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(version?['when'] as String? ?? ''),
      path: ancestors.join(' › '),
      webUrl: webUi.isEmpty ? '' : baseUri.resolve(webUi).toString(),
      syncRun: syncRun,
    );
  }

  factory KnowledgePage.fromRow(Map<String, Object?> row) {
    return KnowledgePage(
      id: row['id']! as String,
      title: row['title']! as String,
      spaceKey: row['space_key']! as String,
      bodyHtml: row['body_html']! as String,
      version: row['version']! as int,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      path: row['page_path']! as String,
      webUrl: row['web_url']! as String,
      syncRun: row['sync_run']! as String,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'title': title,
        'space_key': spaceKey,
        'body_html': bodyHtml,
        'version': version,
        'updated_at': updatedAt?.toIso8601String(),
        'page_path': path,
        'web_url': webUrl,
        'sync_run': syncRun,
      };
}
