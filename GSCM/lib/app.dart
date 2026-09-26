import 'package:flutter/material.dart';

import 'core/connection_store.dart';
import 'core/dashboard_controller.dart';
import 'core/gsc_api.dart';
import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';

class GscmApp extends StatefulWidget {
  const GscmApp({super.key});

  @override
  State<GscmApp> createState() => _GscmAppState();
}

class _GscmAppState extends State<GscmApp> {
  final store = ConnectionStore();
  StoredConnection? connection;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var saved = await store.load();
    // Migrate away from addresses accepted by early prototypes (notably
    // Windows APIPA 169.254/16). Never keep an unsafe endpoint as an
    // auto-login target after upgrading to 1.0.
    if (saved != null && !GscApi.isSafeRemoteUrl(saved.hostUrl)) {
      await store.clear();
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      connection = saved;
      loading = false;
    });
  }

  Future<void> _connected(StoredConnection next) async {
    await store.save(next);
    if (!mounted) return;
    setState(() => connection = next);
  }

  Future<void> _logout() async {
    await store.clear();
    if (!mounted) return;
    setState(() => connection = null);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF67A5FF);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF0D1724),
    );
    final base = ThemeData.dark(useMaterial3: true);
    final theme = base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF07111C),
      canvasColor: const Color(0xFF07111C),
      dividerColor: const Color(0xFF203349),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: const Color(0xFF0E1B29),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF20364E)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF07111C),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0A1521),
        indicatorColor: scheme.primary.withValues(alpha: .16),
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0B1724),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF2A425D))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF2A425D))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)), side: const BorderSide(color: Color(0xFF2B4765)), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12))),
      chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), side: const BorderSide(color: Color(0xFF2A425D))),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GSCM',
      themeMode: ThemeMode.dark,
      darkTheme: theme,
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : connection == null
              ? ConnectScreen(store: store, onConnected: _connected)
              : _ConnectedRoot(connection: connection!, onLogout: _logout),
    );
  }
}

class _ConnectedRoot extends StatefulWidget {
  const _ConnectedRoot({required this.connection, required this.onLogout});
  final StoredConnection connection;
  final Future<void> Function() onLogout;

  @override
  State<_ConnectedRoot> createState() => _ConnectedRootState();
}

class _ConnectedRootState extends State<_ConnectedRoot> with WidgetsBindingObserver {
  late final GscApi api;
  late final DashboardController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    api = GscApi(hostUrl: widget.connection.hostUrl, token: widget.connection.deviceToken);
    controller = DashboardController(api)..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        controller.setForeground(true);
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.setForeground(false);
        return;
      case AppLifecycleState.inactive:
        // Android/iOS can report inactive for short system overlays while the
        // app is still visible. Do not tear down realtime for that transition.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeShell(
        api: api,
        controller: controller,
        connection: widget.connection,
        onLogout: widget.onLogout,
      );
}
