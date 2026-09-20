import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_config.dart';
import '../data/honeychain_store.dart';
import '../models/iot.dart';
import '../theme/app_theme.dart';

/// Backend-connected IoT Simulator (demo/admin tool).
///
/// Drives the real FastAPI simulator endpoints
/// (`/api/v1/iot/simulator/...`) and renders the devices/telemetry the backend
/// actually produced. Every device shown is explicitly labeled SIMULATED —
/// this screen never claims physical sensors.
///
/// Requirements:
/// 1. Run the backend with `uvicorn app.main:app --host 0.0.0.0 --port 8000`.
/// 2. Run the app with `--dart-define=API_BASE_URL=http://localhost:8000`.
/// 3. Sign in as an admin (`admin@honeychain.in` / HoneyChainDemo!1) so
///    `iot.simulator.control` is permitted.
class IotSimulatorScreen extends StatefulWidget {
  const IotSimulatorScreen({super.key});

  @override
  State<IotSimulatorScreen> createState() => _IotSimulatorScreenState();
}

class _IotSimulatorScreenState extends State<IotSimulatorScreen> {
  String? _selectedDevice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = HoneyChainStore.instance;
      if (!store.backendChecked) {
        unawaited(store.refreshBackendIoT());
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _registerDevice(HoneyChainStore store) async {
    final nameController = TextEditingController();
    final hiveController = TextEditingController();
    final result = await showDialog<({String name, String hive})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register simulator device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Device name (e.g. Hive-4 sensor)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hiveController,
              decoration: const InputDecoration(
                labelText: 'Assigned hive id (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              name: nameController.text.trim(),
              hive: hiveController.text.trim(),
            )),
            child: const Text('Register'),
          ),
        ],
      ),
    );
    if (result == null || result.name.isEmpty) return;
    final secrets = await store.registerSimulatorDevice(
      deviceName: result.name,
      assignedHiveId: result.hive,
    );
    if (secrets == null) {
      _snack('Register failed: ${store.backendError ?? 'backend offline'}');
      return;
    }
    _snack('Registered ${secrets['device_id']} · '
        '${secrets['note'] ?? 'key delivered once'}');
  }

  Future<void> _verifyLedger(HoneyChainStore store, String deviceId) async {
    Map<String, dynamic> report;
    try {
      report = await store.backendIotService.deviceLedger(deviceId);
    } on Exception {
      if (!mounted) return;
      _snack('Ledger check failed: ${store.backendError ?? 'backend unreachable'}');
      return;
    }
    if (!mounted) return;
    final issues = (report['issues'] as List?) ?? const [];
    final head = report['head_hash'];
    final headLabel = head == null ? 'n/a' : '$head';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ledger check'),
        content: Text(
          'chain_id: ${report['chain_id'] ?? 'n/a'}\n'
          'head: ${headLabel.length > 12 ? headLabel.substring(0, 12) : headLabel}\n'
          'entries: ${report['event_count'] ?? 'n/a'}\n'
          'integrity: ${report['integrity_ok'] ?? 'n/a'}\n'
          'issues: ${issues.length}${issues.isNotEmpty ? '\nReceipts disagree — a fork was preserved (expected after Fork demo).' : ''}',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _forkDemo(HoneyChainStore store, String deviceId) async {
    final report = await store.simulatorFork(deviceId);
    if (report == null) {
      _snack('Fork failed: ${store.backendError ?? 'backend offline'}');
      return;
    }
    _snack('Fork created: ${report['summary'] ?? 'check ledger per device'}');
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: const Text(
          'IoT Simulator · API',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final devices = store.apiDevices;
            if (_selectedDevice == null && devices.isNotEmpty) {
              _selectedDevice = devices.first.deviceId;
            }
            if (!store.backendChecked && !store.backendConfigured) {
              return _centeredHint(
                'Compiled without API_BASE_URL.\n\n'
                'Run the app with:\n'
                'flutter run --dart-define=API_BASE_URL=http://localhost:8000',
                Icons.dns_outlined,
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _StatusBanner(store: store),
                if (store.backendConfigured && !store.backendOnline) ...[
                  const SizedBox(height: 12),
                  _RetryButton(
                    onPressed: () => store.refreshBackendIoT(),
                  ),
                ],
                if (store.backendOnline && !store.backendSignedIn) ...[
                  const SizedBox(height: 12),
                  _SignInCard(store: store),
                ],
                if (store.backendSignedIn) ...[
                  const SizedBox(height: 12),
                  _SignedInCard(store: store),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Simulator devices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (store.backendSignedIn && store.backendOnline)
                      TextButton.icon(
                        onPressed: () => _registerDevice(store),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Register'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (store.backendError != null && store.backendOnline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      store.backendError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.orangeDark,
                      ),
                    ),
                  ),
                if (devices.isEmpty)
                  const _EmptyDevices()
                else
                  for (final device in devices) ...[
                    _DeviceCard(
                      store: store,
                      device: device,
                      selected: _selectedDevice == device.deviceId,
                      onSelect: () => setState(() {
                        _selectedDevice = device.deviceId;
                      }),
                      onStep: () async {
                        final r = await store.simulatorAction(
                          device.deviceId,
                          'STEP',
                          mode: device.mode,
                          custom: _samplePayload(device),
                        );
                        _snack(r == null
                            ? 'Step failed: ${store.backendError ?? 'offline'}'
                            : 'Emitted 1 event');
                      },
                      onBurst: () async {
                        final r = await store.simulatorAction(
                          device.deviceId,
                          'GENERATE_EVENT',
                          burstCount: 10,
                        );
                        _snack(r == null
                            ? 'Burst failed: ${store.backendError ?? 'offline'}'
                            : 'Emitted ${r['count'] ?? 10} events');
                      },
                      onFork: () => _forkDemo(store, device.deviceId),
                      onLedger: () => _verifyLedger(store, device.deviceId),
                    ),
                    const SizedBox(height: 10),
                  ],
                if (devices.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Device telemetry (from backend)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_selectedDevice == null)
                    const Text(
                      'Pick a device to inspect its events.',
                      style: TextStyle(fontSize: 13, color: AppTheme.inkFaint),
                    )
                  else
                    _TelemetryPanel(
                      store: store,
                      deviceId: _selectedDevice!,
                    ),
                ],
                const SizedBox(height: 28),
              ],
            );
          },
        ),
      ),
    );
  }

  TelemetryPayload _samplePayload(IotDevice device) {
    return TelemetryPayload(
      temperatureC: 38.5,
      humidityPercent: 74,
      hiveWeightKg: 21.4,
      beeActivity: 42,
      acousticFrequencyHz: 262,
      batteryPercent: 96,
      signalStrength: -61,
      extra: const {'note': 'STEP custom sample'},
    );
  }

  Widget _centeredHint(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.inkFaint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.store});

  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.backendConfigured) {
      return _banner(
        color: AppTheme.inkSoft,
        bg: AppTheme.card,
        icon: Icons.info_outline_rounded,
        title: 'Backend not configured',
        detail: 'Compile with --dart-define=API_BASE_URL to enable live data.',
      );
    }
    if (store.backendOnline) {
      return _banner(
        color: AppTheme.green,
        bg: AppTheme.greenSoft,
        icon: Icons.cloud_done_rounded,
        title: 'Backend online · ${ApiConfig.baseUrl}',
        detail: store.backendSignedIn
            ? 'Signed in as ${store.backendDisplayRole}'
            : 'Signed out — sign in (admin@honeychain.in) to control the API.',
      );
    }
    return _banner(
      color: AppTheme.red,
      bg: AppTheme.redSoft,
      icon: Icons.cloud_off_rounded,
      title: 'Backend offline',
      detail: store.backendError ?? 'Check that FastAPI is running on port 8000.',
    );
  }

  Widget _banner({
    required Color color,
    required Color bg,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Retry backend connection'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.orangeDark,
          side: BorderSide(color: AppTheme.orange.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _SignInCard extends StatefulWidget {
  const _SignInCard({required this.store});

  final HoneyChainStore store;

  @override
  State<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<_SignInCard> {
  final TextEditingController _identifier = TextEditingController(
    text: 'admin@honeychain.in',
  );
  final TextEditingController _password = TextEditingController(
    text: 'HoneyChainDemo!1',
  );
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    final role = await widget.store.backendLogin(
      _identifier.text.trim(),
      _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(role != null
            ? 'Signed in (role: $role)'
            : 'Login failed: ${widget.store.backendError ?? 'error'}'),
      ));
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sign in to the backend',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Simulator routes require the admin role.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _identifier,
            decoration: const InputDecoration(
              labelText: 'Identifier',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: _busy ? null : _login,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded, size: 18),
              label: Text(_busy ? 'Signing in…' : 'Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedInCard extends StatelessWidget {
  const _SignedInCard({required this.store});

  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.greenSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Signed in as ${store.backendDisplayRole}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: () => store.backendSignOut(),
            child: const Text('Sign out'),
          ),
          IconButton(
            onPressed: store.backendBusy ? null : () => store.refreshBackendIoT(),
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No devices registered yet.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Admin can register a simulator device, then STEP / BURST to emit '
            'signed events through the real ingestion pipeline.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.store,
    required this.device,
    required this.selected,
    required this.onSelect,
    required this.onStep,
    required this.onBurst,
    required this.onFork,
    required this.onLedger,
  });

  final HoneyChainStore store;
  final IotDevice device;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function() onStep;
  final Future<void> Function() onBurst;
  final Future<void> Function() onFork;
  final Future<void> Function() onLedger;

  static const _modes = [
    'NORMAL', 'TEMPERATURE_STRESS', 'HUMIDITY_STRESS', 'WEIGHT_CHANGE',
    'ACOUSTIC_CHANGE', 'COMBINED_STRESS', 'PERSISTENT_ANOMALY',
    'SENSOR_FAULT', 'OFFLINE', 'RECOVERY', 'RESET',
  ];

  @override
  Widget build(BuildContext context) {
    final accent = device.isOnline ? AppTheme.green : AppTheme.orange;
    SimulatorDeviceStatus? mlInfo;
    for (final s in store.apiSimulatorStatus) {
      if (s.deviceId == device.deviceId) { mlInfo = s; break; }
    }
    final pending = store.apiSimulatorStatus
        .where((s) => s.deviceId == device.deviceId)
        .fold<int>(0, (sum, s) => sum + s.pendingEvents);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(
          color: selected ? accent : AppTheme.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  device.isSimulated
                      ? Icons.memory_rounded
                      : Icons.sensors_rounded,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        '${device.deviceId} · ${device.deviceType} · '
                        'fw ${device.firmwareVersion} · fmt ${device.mode}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: device.deviceStatus,
                  color: device.isOnline ? AppTheme.green : AppTheme.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'seq ${device.sequence} · events ${device.eventCount}'
                '${pending > 0 ? ' · pending $pending' : ''}',
                style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
              const SizedBox(width: 10),
              if (device.batteryPercent != null)
                Text(
                  'batt ${device.batteryPercent!.round()}%',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
              const SizedBox(width: 10),
              if (device.signalStrength != null)
                Text(
                  'rssi ${device.signalStrength!.round()} dBm',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _MlStatusCard(status: mlInfo),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: 'START',
                color: AppTheme.green,
                onTap: () async {
                  await store.simulatorAction(device.deviceId, 'START');
                },
              ),
              _Pill(
                label: 'STOP',
                color: AppTheme.red,
                onTap: () async {
                  await store.simulatorAction(device.deviceId, 'STOP');
                },
              ),
              _Pill(
                label: 'PAUSE',
                color: AppTheme.orange,
                onTap: () async {
                  await store.simulatorAction(device.deviceId, 'PAUSE');
                },
              ),
              _Pill(
                label: 'RESUME',
                color: AppTheme.blue,
                onTap: () async {
                  await store.simulatorAction(device.deviceId, 'RESUME');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in _modes)
                _Pill(
                  label: mode,
                  color: device.mode == mode ? AppTheme.orange : AppTheme.inkSoft,
                  onTap: () async {
                    await store.simulatorMode(device.deviceId, mode);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: 'Emit 1 (STEP)',
                color: AppTheme.teal,
                onTap: onStep,
              ),
              _Pill(
                label: 'Emit 10 (BURST)',
                color: AppTheme.teal,
                onTap: onBurst,
              ),
              _Pill(
                label: 'Fork demo',
                color: AppTheme.purple,
                onTap: onFork,
              ),
              _Pill(
                label: 'Check ledger',
                color: AppTheme.ink,
                onTap: onLedger,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryPanel extends StatelessWidget {
  const _TelemetryPanel({required this.store, required this.deviceId});

  final HoneyChainStore store;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final events = store.apiTelemetryFor(deviceId);
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No telemetry for this device yet (backend produces side-effects on '
          'command; run STEP / BURST).',
          style: TextStyle(fontSize: 13, color: AppTheme.inkFaint, height: 1.4),
        ),
      );
    }
    final shown = events.reversed.take(8).toList();
    return Column(
      children: [
        for (final event in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TelemetryRow(event: event),
          ),
      ],
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({required this.event});

  final IotTelemetry event;

  @override
  Widget build(BuildContext context) {
    final p = event.payload;
    final cells = <(String, String)>[
      if (p.temperatureC != null) ('temp', '${p.temperatureC!.round()}°C'),
      if (p.humidityPercent != null)
        ('hum', '${p.humidityPercent!.round()}%'),
      if (p.hiveWeightKg != null)
        ('wt', '${p.hiveWeightKg!.round()}kg'),
      if (p.beeActivity != null)
        ('act', '${p.beeActivity!.round()}'),
      if (p.batteryPercent != null)
        ('batt', '${p.batteryPercent!.round()}%'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${event.sequence} · ${event.timestamp}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const Icon(Icons.memory_rounded, size: 14, color: AppTheme.teal),
              const SizedBox(width: 4),
              const Text(
                'SIM',
                style: TextStyle(fontSize: 10, color: AppTheme.teal),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cells.isEmpty
                ? 'no numeric payload'
                : cells.map((c) => '${c.$1} ${c.$2}').join(' · '),
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 2),
          Text(
            '${event.eventId} · sha ${event.payloadHash.length > 10 ? event.payloadHash.substring(0, 10) : event.payloadHash}…',
            style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _MlStatusCard extends StatelessWidget {
  const _MlStatusCard({required this.status});

  final SimulatorDeviceStatus? status;

  Color _color(String value) {
    switch (value) {
      case 'HIGH_ATTENTION':
      case 'SENSOR_FAULT':
        return AppTheme.red;
      case 'CHECK_HIVE':
        return AppTheme.orangeDark;
      case 'MONITOR':
        return AppTheme.orange;
      default:
        return AppTheme.green;
    }
  }

  String _label(String value) {
    switch (value) {
      case 'HIGH_ATTENTION': return 'HIGH ATTENTION';
      case 'CHECK_HIVE': return 'CHECK HIVE';
      case 'SENSOR_FAULT': return 'SENSOR FAULT';
      case 'MONITOR': return 'MONITOR';
      default: return 'NORMAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    final color = _color(s.mlStatus);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ML STATUS · ${_label(s.mlStatus)}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
                ),
                if (s.mlReason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(s.mlReason, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.35)),
                ],
                if (s.mlEvidence.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Evidence: ${s.mlEvidence.join(', ')}', style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint)),
                ],
                if (s.mlRecommendation.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('→ ${s.mlRecommendation}', style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}