import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/connection_store.dart';
import '../core/dashboard_controller.dart';
import '../core/gsc_api.dart';
import '../widgets/status_chip.dart';
import 'activity_screen.dart';
import 'automations_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.api,
    required this.controller,
    required this.connection,
    required this.onLogout,
  });

  final GscApi api;
  final DashboardController controller;
  final StoredConnection connection;
  final Future<void> Function() onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String? appVersion;
  late final List<Widget> pages;
  static const titles = ['Command Center', '활동 기록', '자동화', '설정'];

  @override
  void initState() {
    super.initState();
    pages = [
      DashboardScreen(controller: widget.controller),
      ActivityScreen(api: widget.api),
      AutomationsScreen(api: widget.api, controller: widget.controller),
      SettingsScreen(
        api: widget.api,
        controller: widget.controller,
        connection: widget.connection,
        onLogout: widget.onLogout,
      ),
    ];
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => appVersion = info.version);
    } catch (_) {
      // Version text is optional UI metadata. Do not block the dashboard if
      // platform package metadata cannot be read.
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionText = appVersion == null ? 'GSCM · GSC 4.2.1+' : 'GSCM $appVersion · GSC 4.2.1+';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.dns_rounded, size: 21, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titles[index], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            if (index == 0) Text(versionText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ]),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: StatusChip(
                  widget.controller.realtimeUiHealthy ? 'REALTIME' : '재연결 중',
                  icon: widget.controller.realtimeUiHealthy ? Icons.bolt_rounded : Icons.wifi_off_rounded,
                ),
              ),
            ),
          ),
          if (index == 0)
            IconButton(
              onPressed: () => widget.controller.refresh(),
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: '홈'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: '활동'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule_rounded), label: '자동화'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '설정'),
        ],
      ),
    );
  }
}
