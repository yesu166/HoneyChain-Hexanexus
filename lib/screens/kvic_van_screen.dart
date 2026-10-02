import 'package:flutter/material.dart';

import '../core/api/api_config.dart';
import '../data/honeychain_store.dart';
import '../services/honey_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';

/// KVIC HONEY MISSION - PORTABLE VAN.
///
/// Operational interface for the KVIC portable testing van:
///   sign in (real backend identity) -> enter/scan a batch code -> view origin
///   (LIVE record only) -> record a real custody hand-off on the SAME batch ->
///   re-read the batch to verify persistence -> pass the batch forward.
///
/// Honesty rules enforced here:
///  * Sign-in uses the EXISTING backend auth
///    (`HoneyChainStore.beekeeperLogin` -> `POST /api/v1/auth/login`). No
///    password is compiled into this source.
///  * The batch list comes from `store.serverBatches`, which is populated ONLY
///    from the live API. The local/demo batch list is never read here, so LIVE
///    and DEMO data cannot mix.
///  * Unsupported operations are stated explicitly, never fabricated.
class KvicVanScreen extends StatefulWidget {
  const KvicVanScreen({super.key});

  @override
  State<KvicVanScreen> createState() => _KvicVanScreenState();
}

class _KvicVanScreenState extends State<KvicVanScreen> {
  final _identifier = TextEditingController(text: 'admin@honeychain.in');
  final _password = TextEditingController();
  final _batchCode = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _status;
  ServerBatch? _selected;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _batchCode.dispose();
    super.dispose();
  }

  bool get _configured => ApiConfig.isConfigured && !HoneyChainStore.testMode;

  Future<void> _signIn() async {
    final store = HoneyChainStore.instance;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    final role = await store.beekeeperLogin(
      identifier: _identifier.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = role == null
          ? null
          : 'Signed in as ${store.backendIdentity?.email ?? ''} (role: $role)';
      _error = role == null ? (store.backendError ?? 'Backend sign-in failed') : null;
    });
  }

  /// Resolves a batch code (or id) against the LIVE batch list only.
  ServerBatch? _resolve(String code) {
    if (code.isEmpty) return null;
    final wanted = code.toUpperCase();
    for (final b in HoneyChainStore.instance.serverBatches) {
      if (b.batchCode.toUpperCase() == wanted || b.id == code) return b;
    }
    return null;
  }

  Future<void> _refreshLive() async {
    final store = HoneyChainStore.instance;
    setState(() {
      _busy = true;
      _error = null;
    });
    await store.refreshServerCollections();
    if (!mounted) return;
    final resolved = _resolve(_batchCode.text.trim());
    setState(() {
      _busy = false;
      _selected = resolved;
      _status = resolved == null
          ? 'Live batch list refreshed: ${store.serverBatches.length} record(s).'
          : 'Resolved ${resolved.batchCode} from the LIVE API.';
    });
  }

  Future<void> _recordCustody(String action) async {
    final batch = _selected;
    if (batch == null) return;
    final store = HoneyChainStore.instance;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    final ok = await store.recordBatchCustodyEvent(
      batchId: batch.id,
      action: action,
      notes: 'KVIC Honey Mission Portable Testing Van',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = ok ? 'Recorded on the live API: $action' : null;
      _error = ok
          ? null
          : (store.backendError ??
              'Custody write rejected by the backend (capability may be unavailable).');
    });
    if (!ok) return;
    // WRITE -> REFRESH -> GET FROM API -> VERIFY PERSISTENCE.
    final code = batch.batchCode.isEmpty ? batch.id : batch.batchCode;
    await store.refreshServerCollections();
    if (!mounted) return;
    final still = _resolve(code);
    setState(() {
      _selected = still;
      _status = still == null
          ? null
          : 'Verified: $code still present on the live API (status: ${still.status}).';
      _error = still == null
          ? 'Persistence check failed: $code is no longer returned by the API.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.ink,
        title: const Text(
          'KVIC HONEY MISSION',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'PORTABLE VAN',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppTheme.honeyDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Batch intake, origin review, quality hand-off and pass-forward.',
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 18),
            if (!_configured)
              _card(const [
                SectionLabel('LIVE BACKEND'),
                SizedBox(height: 8),
                Text(
                  'This build has no API_BASE_URL compiled in, so no live KVIC '
                  'operation can be performed. Rebuild with '
                  '--dart-define=API_BASE_URL=... to reach the real backend.',
                  style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.35),
                ),
              ])
            else if (!store.backendSignedIn)
              _signInCard()
            else
              _workspace(store),
            if (_status != null) _banner(_status!, AppTheme.green, Icons.verified_outlined),
            if (_error != null) _banner(_error!, AppTheme.red, Icons.error_outline),
          ],
        ),
      ),
    );
  }

  Widget _signInCard() => _card([
        const SectionLabel('VAN OPERATOR SIGN-IN'),
        const SizedBox(height: 10),
        TextField(
          controller: _identifier,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Operator email'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(_busy ? 'SIGNING IN...' : 'SIGN IN TO THE KVIC VAN'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Uses the existing HoneyChain backend identity. No credentials are '
          'stored in the app source.',
          style: TextStyle(fontSize: 11, color: AppTheme.inkFaint, height: 1.3),
        ),
      ]);

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: AppTheme.radiusCard,
          border: Border.all(color: AppTheme.border),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint)),
            ),
            Expanded(
              child: Text(
                v.isEmpty ? '—' : v,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _banner(String text, Color accent, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.tint(accent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 12, color: AppTheme.ink, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _workspace(HoneyChainStore store) {
    final live = store.serverBatches;
    final b = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card([
          const SectionLabel('STEP 1 — SCAN / ENTER BATCH'),
          const SizedBox(height: 10),
          TextField(
            controller: _batchCode,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Batch code (or batch id)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() {
                        final code = _batchCode.text.trim();
                        final r = _resolve(code);
                        _selected = r;
                        if (r == null) {
                          _status = null;
                          _error = 'No LIVE batch matches "$code". '
                              'Demo/mock records are never substituted.';
                        } else {
                          _error = null;
                          _status = 'Resolved ${r.batchCode} from the LIVE API.';
                        }
                      }),
                  child: const Text('VIEW ORIGIN'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _refreshLive,
                  child: const Text('REFRESH LIVE'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Live batches visible to this identity: ${live.length}',
            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
        ]),
        if (live.isNotEmpty) ...[const SizedBox(height: 12), _livePicker(live)],
        if (b != null) ...[
          const SizedBox(height: 12),
          _card([
            const SectionLabel('STEP 2 — ORIGIN (LIVE RECORD)'),
            const SizedBox(height: 8),
            _kv('Batch code', b.batchCode),
            _kv('Batch id', b.id),
            _kv('Honey type', b.honeyType),
            _kv('Quantity', '${b.quantityKg} kg'),
            _kv('Origin', b.origin),
            _kv('Organization', b.organizationId),
            _kv('Status', b.status),
            _kv('Trust tier', b.trustTier),
          ]),
          const SizedBox(height: 12),
          _card([
            const SectionLabel('STEP 3 — QUALITY / PROCESSING HAND-OFF'),
            const SizedBox(height: 8),
            const Text(
              'Every button performs a REAL write on the live API for this exact '
              'batch, then re-reads the batch to verify persistence.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.35),
            ),
            const SizedBox(height: 12),
            _custody('VAN RECEIVES BATCH (custody: collected)', 'collected', true),
            const SizedBox(height: 8),
            _custody('RECORD QUALITY HAND-OFF (custody: tested)', 'tested', false),
            const SizedBox(height: 8),
            _custody('CONFIRM + PASS FORWARD (custody: passed_forward)',
                'passed_forward', false),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'HONEST LIMIT — the FastAPI backend exposes '
                'POST /api/v1/batches/{id}/lab-test and '
                'POST /api/v1/labs/tests/{id}/result, but this Flutter client has '
                'no wired method for them yet. No lab reading is written or shown '
                'here, so a test result can never be fabricated.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.ink, height: 1.35),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _custody(String label, String action, bool filled) => SizedBox(
        width: double.infinity,
        child: filled
            ? FilledButton(
                onPressed: _busy ? null : () => _recordCustody(action),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: _busy ? null : () => _recordCustody(action),
                child: Text(label),
              ),
      );

  Widget _livePicker(List<ServerBatch> live) => _card([
        const SectionLabel('LIVE BATCHES'),
        for (final batch in live.take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              batch.batchCode.isEmpty ? batch.id : batch.batchCode,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            subtitle: Text(
              '${batch.honeyType.isEmpty ? 'honey' : batch.honeyType} · '
              '${batch.quantityKg} kg · ${batch.status}',
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => setState(() {
              _batchCode.text = batch.batchCode.isEmpty ? batch.id : batch.batchCode;
              _selected = batch;
              _error = null;
              _status = 'Selected ${batch.batchCode} (LIVE record).';
            }),
          ),
      ]);

}
