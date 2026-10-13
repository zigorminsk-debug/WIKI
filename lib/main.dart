import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'models/confluence_settings.dart';
import 'models/knowledge_page.dart';
import 'services/background_sync.dart';
import 'services/confluence_client.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.configureForCurrentPlatform();
  await BackgroundSyncService().initialize();
  runApp(const KnowledgeBaseApp());
}

class KnowledgeBaseApp extends StatefulWidget {
  const KnowledgeBaseApp({super.key});

  @override
  State<KnowledgeBaseApp> createState() => _KnowledgeBaseAppState();
}

class _KnowledgeBaseAppState extends State<KnowledgeBaseApp> {
  final _controller = KnowledgeBaseController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Локальная база знаний',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF145DA0)),
        useMaterial3: true,
      ),
      home: AppShell(controller: _controller),
    );
  }
}

class KnowledgeBaseController extends ChangeNotifier {
  KnowledgeBaseController({
    DatabaseService? databaseService,
    SettingsService? settingsService,
    SyncService? syncService,
    BackgroundSyncService? backgroundSyncService,
  })  : _databaseService = databaseService ?? DatabaseService.instance,
        _settingsService = settingsService ?? SettingsService.instance,
        _syncService = syncService ?? SyncService(),
        _backgroundSyncService = backgroundSyncService ?? BackgroundSyncService();

  final DatabaseService _databaseService;
  final SettingsService _settingsService;
  final SyncService _syncService;
  final BackgroundSyncService _backgroundSyncService;

  ConfluenceSettings settings = const ConfluenceSettings.empty();
  List<KnowledgePage> pages = const <KnowledgePage>[];
  bool isLoading = true;
  bool isSyncing = false;
  String? transientError;
  Timer? _desktopTimer;

  Future<void> initialize() async {
    settings = await _settingsService.load();
    await refreshPages();
    isLoading = false;
    notifyListeners();

    // Android's worker is configured after the app has access to the saved
    // settings. On Windows the app itself provides the in-process daily timer.
    await _backgroundSyncService.updateSchedule();
    _desktopTimer = Timer.periodic(const Duration(hours: 24), (_) => synchronize(silent: true));

    final stale = settings.lastSyncAt == null || DateTime.now().difference(settings.lastSyncAt!) >= const Duration(hours: 24);
    if (settings.isConfigured && stale) {
      unawaited(synchronize(silent: true));
    }
  }

  Future<void> refreshPages([String query = '']) async {
    pages = await _databaseService.searchPages(query);
    notifyListeners();
  }

  Future<bool> saveSettings({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalizedUrl = serverUrl.trim();
    if (normalizedUrl.isEmpty || username.trim().isEmpty) {
      transientError = 'Заполните адрес сервера и логин.';
      notifyListeners();
      return false;
    }
    try {
      final candidate = normalizedUrl.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? normalizedUrl
          : 'https://$normalizedUrl';
      final uri = Uri.parse(candidate);
      if (!uri.hasScheme || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException();
      }
    } on FormatException {
      transientError = 'Адрес должен начинаться с http:// или https:// и содержать IP/имя сервера.';
      notifyListeners();
      return false;
    }

    settings = settings.copyWith(serverUrl: normalizedUrl, username: username.trim(), clearLastError: true);
    await _settingsService.save(settings, password: password.trim().isEmpty ? null : password);
    await _backgroundSyncService.updateSchedule();
    transientError = null;
    notifyListeners();
    return true;
  }

  Future<void> synchronize({bool silent = false}) async {
    if (isSyncing || !settings.isConfigured) {
      return;
    }
    isSyncing = true;
    transientError = null;
    notifyListeners();
    try {
      await _syncService.synchronize();
      settings = await _settingsService.load();
      await refreshPages();
    } on ConfluenceException catch (error) {
      settings = await _settingsService.load();
      transientError = error.message;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _desktopTimer?.cancel();
    super.dispose();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final KnowledgeBaseController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final pageTitle = _selectedIndex == 0 ? 'База знаний' : 'Настройки';
        return Scaffold(
          appBar: AppBar(
            title: Text(pageTitle),
            actions: <Widget>[
              if (_selectedIndex == 0)
                IconButton(
                  tooltip: 'Синхронизировать сейчас',
                  onPressed: widget.controller.isSyncing || !widget.controller.settings.isConfigured
                      ? null
                      : () => unawaited(widget.controller.synchronize()),
                  icon: widget.controller.isSyncing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (widget.controller.transientError != null)
                _ErrorBanner(
                  text: widget.controller.transientError!,
                  onDismiss: () {
                    widget.controller.transientError = null;
                    widget.controller.notifyListeners();
                  },
                ),
              Expanded(
                child: _selectedIndex == 0
                    ? LibraryScreen(controller: widget.controller)
                    : SettingsScreen(
                        controller: widget.controller,
                        onSaved: () => setState(() => _selectedIndex = 0),
                      ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Страницы'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Настройки'),
            ],
          ),
        );
      },
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});

  final KnowledgeBaseController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_search);
  }

  void _search() {
    unawaited(widget.controller.refreshPages(_searchController.text));
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_search)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.settings.isConfigured) {
      return const _EmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'Подключите Confluence',
        message: 'Откройте «Настройки», укажите адрес сервера, логин и пароль, затем запустите первую синхронизацию.',
      );
    }
    return Column(
      children: <Widget>[
        _SyncSummary(settings: controller.settings, pageCount: controller.pages.length),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _searchController.clear,
                    ),
              hintText: 'Поиск по странице, пространству и тексту',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: controller.pages.isEmpty
              ? RefreshIndicator(
                  onRefresh: () => controller.synchronize(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: const <Widget>[
                      SizedBox(height: 72),
                      _EmptyState(
                        icon: Icons.cloud_download_outlined,
                        title: 'В кэше пока нет страниц',
                        message: 'Нажмите кнопку синхронизации. Страницы появятся здесь и останутся доступны без сети.',
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => controller.synchronize(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: controller.pages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final page = controller.pages[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(page.spaceKey.isEmpty ? '?' : page.spaceKey.substring(0, 1).toUpperCase())),
                        title: Text(page.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          <String>[
                            if (page.spaceKey.isNotEmpty) page.spaceKey,
                            if (page.path.isNotEmpty) page.path,
                            if (page.updatedAt != null) 'обновлено ${formatDate(page.updatedAt!)}',
                          ].join('  •  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PageReaderScreen(page: page))),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller, required this.onSaved});

  final KnowledgeBaseController controller;
  final VoidCallback onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  var _obscurePassword = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.controller.settings.serverUrl);
    _usernameController = TextEditingController(text: widget.controller.settings.username);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveAndSync() async {
    setState(() => _saving = true);
    final saved = await widget.controller.saveSettings(
      serverUrl: _serverController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );
    if (saved) {
      await widget.controller.synchronize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены. Синхронизация запущена.')));
        widget.onSaved();
      }
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Подключение к Confluence', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Данные сохраняются только на этом устройстве. Пароль хранится в защищённом хранилище ОС.'),
        const SizedBox(height: 24),
        TextField(
          controller: _serverController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Адрес сервера',
            hintText: 'https://192.168.1.20:8443/confluence',
            prefixIcon: Icon(Icons.dns_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Логин Confluence',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Пароль${settings.isConfigured ? ' (оставьте пустым, чтобы не менять)' : ''}',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const _SecurityNotice(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving || widget.controller.isSyncing ? null : _saveAndSync,
          icon: _saving || widget.controller.isSyncing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_and_sync),
          label: const Text('Сохранить и синхронизировать'),
        ),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 10),
        Text('Автоматическая синхронизация', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Каждые 24 часа при наличии сети. Android запускает задачу в фоне с допустимой системной задержкой; на Windows — при открытом приложении и при следующем запуске.'),
      ],
    );
  }
}

class PageReaderScreen extends StatelessWidget {
  const PageReaderScreen({super.key, required this.page});

  final KnowledgePage page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(page.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: <Widget>[
            if (page.spaceKey.isNotEmpty)
              Chip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(page.spaceKey),
              ),
            if (page.path.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(page.path, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (page.updatedAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('Версия ${page.version} • обновлено ${formatDate(page.updatedAt!)}', style: Theme.of(context).textTheme.bodySmall),
            ],
            const Divider(height: 32),
            Html(data: page.bodyHtml),
          ],
        ),
      ),
    );
  }
}

class _SyncSummary extends StatelessWidget {
  const _SyncSummary({required this.settings, required this.pageCount});

  final ConfluenceSettings settings;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final status = settings.lastSyncAt == null ? 'Синхронизация ещё не выполнена' : 'Обновлено ${formatDate(settings.lastSyncAt!)}';
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.offline_pin_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text('$status • $pageCount стр. доступны офлайн')),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            IconButton(onPressed: onDismiss, icon: const Icon(Icons.close), tooltip: 'Закрыть'),
          ],
        ),
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Для внутреннего HTTP-сервера используйте адрес с http://; для рабочих данных предпочтителен HTTPS с доверенным сертификатом. Пароль не хранится в SQLite и не отправляется в URL.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
}
