import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/router/app_router.dart';
import 'package:hey_dane/app/core/theme/dane_theme.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class HeyDaneApp extends ConsumerStatefulWidget {
  const HeyDaneApp({
    super.key,
    this.initialLocation = '/splash',
  });

  final String initialLocation;

  @override
  ConsumerState<HeyDaneApp> createState() => _HeyDaneAppState();
}

class _HeyDaneAppState extends ConsumerState<HeyDaneApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(initialLocation: widget.initialLocation);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppIdentity.appName,
      debugShowCheckedModeBanner: false,
      theme: DaneTheme.lightTheme,
      darkTheme: DaneTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
