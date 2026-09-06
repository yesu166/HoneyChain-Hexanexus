import 'dart:async';

import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/speech/speech_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/section_label.dart';

/// Voice-first harvest entry.
///
/// Uses browser/device speech recognition when available (the Web Speech API
/// on the web build) and always provides a manual fallback so the demo is
/// reliable on any platform. It never fakes audio: if speech is unsupported
/// the microphone simply fills from the manual controls instead.
class VoiceHarvestScreen extends StatefulWidget {
  const VoiceHarvestScreen({super.key});

  @override
  State<VoiceHarvestScreen> createState() => _VoiceHarvestScreenState();
}

class _VoiceHarvestScreenState extends State<VoiceHarvestScreen>
    with SingleTickerProviderStateMixin {
  final SpeechRecognitionService _speech = createSpeechRecognitionService();
  late AnimationController _pulse;
  List<StreamSubscription<String>>? _subs;

  String _status = '';
  String _transcript = '';
  bool _listening = false;
  String? _hiveId;
  String _hiveName = '';
  double _qty = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    _subs?.forEach((s) => s.cancel());
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final supported = _speech.isSupported;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('voice.entry.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          const SizedBox(height: 6),
          _micSection(supported),
          const SizedBox(height: 24),
          _transcriptBox(),
          const SizedBox(height: 24),
          if (_hiveId != null)
            _recognizedSummary(store)
          else
            SectionLabel(store.tr('voice.choose.hive')),
          if (_hiveId == null) ...[
            const SizedBox(height: 10),
            _hiveSelector(store),
          ],
          const SizedBox(height: 22),
          SectionLabel(store.tr('voice.qty.label')),
          const SizedBox(height: 10),
          _quantityRow(),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                disabledBackgroundColor: AppTheme.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.check_rounded, size: 20),
              label: Text(
                store.tr('voice.record.harvest'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  bool get _canSave => _hiveId != null && _qty > 0;

  Widget _micSection(bool supported) {
    final store = HoneyChainStore.instance;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _listening ? (_pulse.value * 0.5) : 0.0;
            return Container(
              width: 150 + t * 40,
              height: 150 + t * 40,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: _listening ? _stop : _start,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    color: _listening ? AppTheme.red : AppTheme.orange,
                    shape: BoxShape.circle,
                    boxShadow: const [AppTheme.shadowCard],
                  ),
                  child: Icon(
                    _listening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          supported
              ? (_listening
                  ? store.tr('voice.listening.speak')
                  : store.tr('voice.tap.listen'))
              : store.tr('voice.unavailable'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        if (!supported) ...[
          const SizedBox(height: 6),
          Text(
            store.tr('voice.use.fields'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
        ],
      ],
    );
  }

  Widget _transcriptBox() {
    if (_transcript.isEmpty && _status.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_status.isNotEmpty)
            Text(
              _status,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.orangeDark,
              ),
            ),
          if (_status.isNotEmpty) const SizedBox(height: 6),
          Text(
            _transcript.isEmpty ? _status : '"$_transcript"',
            style: const TextStyle(fontSize: 15, color: AppTheme.ink),
          ),
        ],
      ),
    );
  }

  Widget _recognizedSummary(HoneyChainStore store) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.green),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              store
                  .tr('voice.recognized')
                  .replaceFirst('{hive}', _hiveName)
                  .replaceFirst('{kg}', formatKg(_qty)),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hiveSelector(HoneyChainStore store) {
    final hives = store.hives;
    return DropdownButtonFormField<String>(
      initialValue: _hiveId,
      isExpanded: true,
      items: [
        for (final h in hives)
          DropdownMenuItem(
            value: h.id,
            child: Text(
              h.detail.isEmpty ? h.name : '${h.name} · ${h.detail}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.ink),
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        setState(() {
          _hiveId = id;
          for (final h in hives) {
            if (h.id == id) {
              _hiveName = h.name;
              break;
            }
          }
        });
      },
      decoration: _fieldDecoration(),
    );
  }

  Widget _quantityRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusField,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _step(Icons.remove_rounded, () {
            setState(() => _qty = (_qty - 0.5).clamp(0, 100.0));
          }),
          Expanded(
            child: Text(
              '${formatKg(_qty)} kg',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          _step(Icons.add_rounded, () {
            setState(() => _qty = (_qty + 0.5).clamp(0, 100.0));
          }),
        ],
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: AppTheme.orangeSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.orangeDark, size: 22),
      ),
    );
  }

  Future<void> _start() async {
    if (!_speech.isSupported) return;
    _pulse.repeat();
    setState(() {
      _listening = true;
      _status = HoneyChainStore.instance.tr('voice.listening');
      _transcript = '';
    });
    final sub = _speech.listen().listen(
      (text) {
        if (!mounted) return;
        setState(() => _transcript = text);
      },
      onDone: () {
        if (!mounted) return;
        _stop();
        _parse();
      },
    );
    _subs = [sub];
  }

  void _stop() {
    _pulse.stop();
    _pulse.reset();
    if (!mounted) return;
    setState(() => _listening = false);
  }

  /// Best-effort interpretation of the transcript into hive + quantity.
  /// Pure string heuristics — the demo does not claim a trained NLP model.
  void _parse() {
    final text = _transcript.trim();
    final store = HoneyChainStore.instance;
    if (text.isEmpty) {
      setState(() => _status = store.tr('voice.no.speech'));
      return;
    }
    final lower = text.toLowerCase();

    String? matchedHive;
    for (final h in store.hives) {
      final hiveKey = 'hive ${h.name.toLowerCase().trim()}';
      final parts = h.name.toLowerCase().trim().split(' ');
      final match =
          lower.contains(hiveKey) ||
          (parts.isNotEmpty && lower.contains(parts[0])) ||
          (h.detail.isNotEmpty && lower.contains(h.detail.toLowerCase()));
      if (match) {
        matchedHive = h.id;
        _hiveName = h.name;
        break;
      }
    }

    final qty = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kg|kilo|kilos)').firstMatch(lower);
    final hv = qty?.group(1);
    final qtyVal = hv != null ? double.tryParse(hv) : null;

    if (matchedHive == null && qtyVal == null) {
      setState(() => _status = store.tr('voice.could.not.read'));
      return;
    }

    setState(() {
      _status = store.tr('voice.got.it');
      if (matchedHive != null) _hiveId = matchedHive;
      if (qtyVal != null) _qty = qtyVal.clamp(0, 100.0);
    });
  }

  Future<void> _save() async {
    final store = HoneyChainStore.instance;
    Hive? hive;
    for (final h in store.hives) {
      if (h.id == _hiveId) {
        hive = h;
        break;
      }
    }
    if (hive == null) return;
    store.recordHarvest(hive: hive, quantityKg: _qty, date: DateTime.now());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(HoneyChainStore.instance.tr('voice.harvest.recorded')),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppTheme.card,
      hintStyle: const TextStyle(color: AppTheme.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.orange, width: 1.6),
      ),
    );
  }
}