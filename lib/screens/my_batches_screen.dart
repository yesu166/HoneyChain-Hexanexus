import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../widgets/batch_card.dart';
import '../widgets/brand_header.dart';
import '../widgets/section_header.dart';
import 'batch_detail_screen.dart';
import 'create_batch_screen.dart';

class MyBatchesScreen extends StatelessWidget {
  const MyBatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batches = store.batches;
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('my.batches.title'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('my.batches.subtitle')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateBatchScreen()),
                    ).then((created) {
                      if (created == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(store.tr('my.batches.created.snackbar'))),
                        );
                      }
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: Text(store.tr('my.batches.create')),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: store.tr('my.batches.all').replaceFirst('{count}', '${batches.length}'),
                seeAllLabel: '',
              ),
              const SizedBox(height: 12),
              if (batches.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      store.tr('my.batches.empty'),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                for (final batch in batches) ...[
                  BatchCard(
                    batch: batch,
                    extra: '${store.tr('my.batches.created.prefix')} ${_shortDate(batch.createdAt)}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: batch)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }

  String _shortDate(DateTime t) => '${t.day} Aug ${t.year}';
}
