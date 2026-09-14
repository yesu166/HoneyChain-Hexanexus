import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../services/platform_api_service.dart';
import '../../theme/app_theme.dart';

/// Platform Oversight -> Audit.
///
/// Immutable, backend-persisted platform audit trail (`GET /api/v1/platform/audit`).
/// Each row shows who (actor role/user) did what against which target, at what
/// time. Nothing here is invented — it is the server's recorded history.
class PlatformAuditScreen extends StatefulWidget {
  const PlatformAuditScreen({super.key});

  @override
  State<PlatformAuditScreen> createState() => _PlatformAuditScreenState();
}

class _PlatformAuditScreenState extends State<PlatformAuditScreen> {
  List<PlatformAuditEvent>? _events;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = HoneyChainStore.instance;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final events = await store.platformApi.listAudit(limit: 100);
      if (!mounted) return;
      setState(() => _events = events);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Audit trail',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _load,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 22),
                  tooltip: 'Refresh audit trail',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Every platform action is recorded server-side.',
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (_events == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_events!.isEmpty)
              const _EmptyCard(text: 'No audit events recorded yet.')
            else
              for (final event in _events!) ...[
                _AuditRow(event: event),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event});

  final PlatformAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(event.action);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(event.action), color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendlyAction(event.action),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (event.targetKey.isNotEmpty) event.targetKey,
                    if (event.targetType.isNotEmpty) event.targetType,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
                ),
                const SizedBox(height: 6),
                Text(
                  '${event.actorRole} · ${event.actorUserId}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _shortTs(event.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkFaint,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _actionTag(event.action),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _accentFor(String action) {
    if (action.contains('create') || action.contains('assign')) {
      return AppTheme.green;
    }
    if (action.contains('revoke') ||
        action.contains('suspend') ||
        action.contains('deactivate')) {
      return AppTheme.red;
    }
    if (action.contains('reinstate') || action.contains('activate')) {
      return AppTheme.honeyDark;
    }
    return AppTheme.blue;
  }

  static IconData _iconFor(String action) {
    if (action.contains('assign')) return Icons.person_add_alt_1_outlined;
    if (action.contains('revoke')) return Icons.person_remove_outlined;
    if (action.contains('suspend')) return Icons.pause_circle_outline;
    if (action.contains('reinstate')) return Icons.play_circle_outline;
    if (action.contains('deactivate')) return Icons.cancel_outlined;
    if (action.contains('activate')) return Icons.check_circle_outline;
    if (action.contains('create')) return Icons.add_rounded;
    return Icons.history_rounded;
  }

  static String _friendlyAction(String action) {
    const map = {
      'organization.create': 'Organization created',
      'organization.activate': 'Organization activated',
      'organization.suspend': 'Organization suspended',
      'organization.deactivate': 'Organization deactivated',
      'organization.onboard_admin': 'Admin invited',
      'organization.revoke_admin': 'Admin invite revoked',
      'membership.assign': 'Beekeeper assigned',
      'membership.revoke': 'Membership revoked',
      'member.suspend': 'Member suspended',
      'member.reinstate': 'Member reinstated',
    };
    return map[action] ?? action.replaceAll('_', ' ');
  }

  static String _actionTag(String action) {
    final cleaned = action.startsWith('organization.')
        ? action.substring('organization.'.length)
        : action.startsWith('membership.')
            ? action.substring('membership.'.length)
            : action.startsWith('member.')
                ? action.substring('member.'.length)
                : action;
    return cleaned.toUpperCase();
  }

  String _shortTs(String ts) {
    if (ts.isEmpty) return '';
    final parsed = DateTime.tryParse(ts);
    if (parsed == null) return ts.length > 16 ? ts.substring(0, 16) : ts;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.red, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Could not load the audit trail',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      ),
    );
  }
}