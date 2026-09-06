import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/theme/app_theme.dart';

class TreatmentTrackerScreen extends StatelessWidget {
  const TreatmentTrackerScreen({super.key, required this.hiveId});
  final String hiveId;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('bh.treatment.title'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final treatments = store.treatmentsFor(hiveId);
            final followUps = store.followUpsFor(hiveId);
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        store.tr('bh.treatment.title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_rounded,
                        color: AppTheme.orange,
                      ),
                      onPressed: () => _showAddTreatment(context, store),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (treatments.isEmpty && followUps.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: AppTheme.radiusCard,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Center(
                      child: Text(
                        store.tr('bh.treatment.no.treatments'),
                        style: const TextStyle(color: AppTheme.inkFaint),
                      ),
                    ),
                  )
                else ...[
                  for (final t in treatments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TreatmentTile(record: t, store: store),
                    ),
                  for (final f in followUps.where(
                    (f) => f.status == FollowUpStatus.pending,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FollowUpTile(followUp: f, store: store),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddTreatment(BuildContext context, HoneyChainStore store) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.tr('bh.treatment.add'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: store.tr('bh.treatment.note'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) return;
                  store.addTreatment(
                    hiveId: hiveId,
                    treatment: ctrl.text.trim(),
                  );
                  Navigator.of(context).pop();
                },
                child: Text(
                  store.tr('action.confirm'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _TreatmentTile extends StatelessWidget {
  const _TreatmentTile({required this.record, required this.store});
  final TreatmentRecord record;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final isActive = record.status == TreatmentStatus.active;
    final color = isActive ? AppTheme.orange : AppTheme.green;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.treatment,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? store.tr('bh.treatment.active')
                      : store.tr('bh.treatment.completed'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            TextButton(
              onPressed: () => store.completeTreatment(record.id),
              child: Text(
                store.tr('bh.treatment.mark.done'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.followUp, required this.store});
  final BeeHealthFollowUp followUp;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 18, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              followUp.note,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: () => store.completeFollowUp(followUp.id),
            child: Text(
              store.tr('bh.treatment.mark.done'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
