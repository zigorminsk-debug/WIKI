import 'package:confluence_kb/models/confluence_settings.dart';
import 'package:confluence_kb/models/knowledge_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a pasted content endpoint to the Confluence root', () {
    const settings = ConfluenceSettings(
      serverUrl: 'https://10.20.30.40/confluence/rest/api/content',
      username: 'reader',
    );

    expect(settings.baseUri.toString(), 'https://10.20.30.40/confluence');
  });

  test('adds HTTPS when an address has no scheme', () {
    const settings = ConfluenceSettings(serverUrl: 'wiki.internal:8443', username: 'reader');

    expect(settings.baseUri.toString(), 'https://wiki.internal:8443');
  });

  test('maps a Confluence API page including hierarchy and storage body', () {
    final page = KnowledgePage.fromConfluence(
      <String, dynamic>{
        'id': '1234',
        'title': 'Инструкция',
        'body': <String, dynamic>{'storage': <String, dynamic>{'value': '<p>Офлайн-текст</p>'}},
        'version': <String, dynamic>{'number': 7, 'when': '2026-10-13T12:00:00.000Z'},
        'space': <String, dynamic>{'key': 'OPS'},
        'ancestors': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'База знаний'},
          <String, dynamic>{'title': 'Серверы'},
        ],
        '_links': <String, dynamic>{'webui': '/display/OPS/Instruction'},
      },
      syncRun: 'run-1',
      baseUri: Uri.parse('https://wiki.example/confluence'),
    );

    expect(page.title, 'Инструкция');
    expect(page.spaceKey, 'OPS');
    expect(page.path, 'База знаний › Серверы');
    expect(page.bodyHtml, '<p>Офлайн-текст</p>');
    expect(page.version, 7);
  });
}
