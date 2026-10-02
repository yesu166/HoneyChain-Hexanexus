import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/api/api_config.dart';
import 'core/supabase/supabase_client.dart';
import 'data/auth.dart';
import 'data/honeychain_store.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/platform/platform_shell.dart';
import 'screens/who_are_you_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configIssue = ApiConfig.startUpIssue;
  if (configIssue != null) {
    throw StateError(configIssue);
  }
  await HoneySupabase.ensureInitialized();
  runApp(const HoneyChainApp());
}

class HoneyChainApp extends StatefulWidget {
  const HoneyChainApp({super.key});

  @override
  State<HoneyChainApp> createState() => _HoneyChainAppState();
}

class _HoneyChainAppState extends State<HoneyChainApp>
    with WidgetsBindingObserver {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await HoneyChainStore.instance.ensureStarted();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      HoneyChainStore.instance.refreshConnectivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HoneyChain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: _RootGate(ready: _ready),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate({required this.ready});

  final bool ready;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  // Which entry was chosen on the first-launch role gate. `null` until the
  // user picks a role; `beekeeper` shows the phone + OTP login in place of the
  // gate (no extra route) so a successful login swaps cleanly to the shell.
  bool _beekeeperChosen = false;
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    final store = HoneyChainStore.instance;
    _wasLoggedIn = store.loggedIn;
    store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    HoneyChainStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  // When the beekeeper logs out, return the app to the first-launch role gate.
  void _onStoreChanged() {
    final store = HoneyChainStore.instance;
    if (_wasLoggedIn && !store.loggedIn) {
      setState(() {
        _wasLoggedIn = store.loggedIn;
        _beekeeperChosen = false;
      });
    } else {
      _wasLoggedIn = store.loggedIn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    if (!widget.ready) {
      return const Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HoneycombMark(),
              SizedBox(height: 18),
              Text(
                'HONEYCHAIN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppTheme.honeyDark,
                ),
              ),
              SizedBox(height: 10),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.honeyGold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loggedIn) {
          // Route by the session's ACTIVE WORKSPACE (set at login from the
          // backend role, switchable from the More tab) — not by role alone,
          // so a platform-oversight user who switched to Consumer keeps the
          // consumer portal instead of being forced back into oversight.
          switch (store.activeWorkspace) {
            case Workspace.platform:
              return const PlatformShell();
            case Workspace.beekeeper:
            case Workspace.organization:
            case Workspace.lab:
            case Workspace.processor:
            case Workspace.buyer:
            case Workspace.institution:
            case Workspace.consumer:
              return const MainShell();
          }
        }
        if (_beekeeperChosen) return const LoginScreen();
        return WhoAreYouScreen(
          onBeekeeper: () => setState(() => _beekeeperChosen = true),
          onKvicVan: () => Navigator.of(context).push(kvicVanRoute()),
        );
      },
    );
  }
}

/// The six-hexagon honeycomb flower built in code. Kept dependency-free so the
/// mark renders identically everywhere (launch screen, login, share cards).
class _HoneycombMark extends StatelessWidget {
  const _HoneycombMark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(96),
      painter: _HoneycombPainter(),
    );
  }
}

/// Draws a center hexagon plus six neighbors wound into a honeycomb flower.
class _HoneycombPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.11;
    final neighborGap = radius * 2 * 0.866 * 2;

    final centerPaint = Paint()..color = AppTheme.honeyGold;
    final neighborPaint = Paint()
      ..color = AppTheme.honeyDark.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.32
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_hexagonPath(center, radius), centerPaint);
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final offset = Offset(
        math.cos(angle) * neighborGap,
        math.sin(angle) * neighborGap,
      );
      canvas.drawPath(_hexagonPath(center + offset, radius), neighborPaint);
    }
  }

  static Path _hexagonPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final point = center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HoneycombPainter oldDelegate) => false;
}
