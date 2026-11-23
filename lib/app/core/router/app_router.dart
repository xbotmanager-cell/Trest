import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/features/about/about_screen.dart';
import 'package:hey_dane/app/features/assistant/assistant_screen.dart';
import 'package:hey_dane/app/features/automation/automation_screen.dart';
import 'package:hey_dane/app/features/chat/chat_screen.dart';
import 'package:hey_dane/app/features/memory/memory_screen.dart';
import 'package:hey_dane/app/features/permissions/permissions_screen.dart';
import 'package:hey_dane/app/features/settings/settings_screen.dart';
import 'package:hey_dane/app/features/splash/splash_screen.dart';
import 'package:hey_dane/app/features/voice/presentation/live_voice_screen.dart';
import 'package:hey_dane/app/shared/widgets/dane_shell.dart';

GoRouter createAppRouter({String initialLocation = '/splash'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return DaneShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assistant',
                builder: (context, state) => const AssistantScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (context, state) => const ChatScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/permissions',
                builder: (context, state) => const PermissionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/automation',
                builder: (context, state) => const AutomationScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/live-voice',
        builder: (context, state) => const LiveVoiceScreen(),
      ),
      GoRoute(
        path: '/memory',
        builder: (context, state) => const MemoryScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
    ],
  );
}
