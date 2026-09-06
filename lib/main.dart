import 'package:flutter/material.dart';

import 'data/honeychain_store.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/who_are_you_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loggedIn) return const MainShell();
        if (_beekeeperChosen) return const LoginScreen();
        return WhoAreYouScreen(
          onBeekeeper: () => setState(() => _beekeeperChosen = true),
        );
      },
    );
  }
}