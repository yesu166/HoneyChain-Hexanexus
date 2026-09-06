import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import 'passport_screen.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final listings = store.batches
            .where((batch) => batch.status == BatchStatus.labVerified || batch.status == BatchStatus.listed)
            .toList();
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('marketplace.appbar'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('marketplace.subtitle')),
              const SizedBox(height: 8),
              Text(store.tr('marketplace.description'), style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 20),
              SectionHeader(title: store.tr('marketplace.listings').replaceFirst('{count}', '${listings.length}'), seeAllLabel: ''),
              const SizedBox(height: 12),
              if (listings.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(store.tr('marketplace.empty'), style: const TextStyle(color: Colors.black54))))
              else
                for (final batch in listings) ...[
                  _ListingCard(batch: batch),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final listing = store.marketplaceListings.where((item) => item.batchId == batch.id).firstOrNull;
    final isListed = listing != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hexagon_outlined, color: AppTheme.honeyDark, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(batch.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                StatusPill(label: isListed ? StatusPill.listed : StatusPill.verified),
              ],
            ),
            const SizedBox(height: 10),
            Text(batch.honeyType, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${batch.origin}  ·  ${batch.quantityKg.toStringAsFixed(1)} kg', style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 4),
            Text(store.tr('marketplace.producer'), style: const TextStyle(color: Colors.black45, fontSize: 12)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassportScreen(batch: batch))),
                    icon: const Icon(Icons.qr_code),
                    label: Text(store.tr('marketplace.view.passport')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isListed
                        ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestPurchaseScreen(listing: listing)))
                        : () {
                            store.listV2Batch(batch);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('marketplace.listed.toast').replaceFirst('{batch}', batch.code))));
                          },
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text(isListed ? store.tr('marketplace.request.purchase') : store.tr('marketplace.list.batch')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RequestPurchaseScreen extends StatefulWidget {
  const RequestPurchaseScreen({super.key, required this.listing});
  final MarketplaceListing listing;
  @override
  State<RequestPurchaseScreen> createState() => _RequestPurchaseScreenState();
}

class _RequestPurchaseScreenState extends State<RequestPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _buyer = TextEditingController(text: 'Aarav Mehta');
  final _quantity = TextEditingController(text: '5');
  final _message = TextEditingController();

  @override
  void dispose() {
    _buyer.dispose();
    _quantity.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
        appBar: AppBar(title: Text(store.tr('marketplace.request.purchase'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(store.tr('marketplace.request.purchase'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(store.tr('marketplace.listing.for'), style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 20),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(controller: _buyer, decoration: InputDecoration(labelText: store.tr('marketplace.buyer'))),
                      const SizedBox(height: 14),
                      TextFormField(controller: _quantity, keyboardType: TextInputType.number, validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0 ? null : store.tr('marketplace.valid.qty'), decoration: InputDecoration(labelText: store.tr('register.batch.quantity'))),
                      const SizedBox(height: 14),
                      TextFormField(controller: _message, decoration: InputDecoration(labelText: store.tr('marketplace.message.optional'))),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;
                          HoneyChainStore.instance.requestPurchase(widget.listing, _buyer.text.trim(), double.parse(_quantity.text), _message.text.trim());
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('marketplace.sent'))));
                          Navigator.pop(context);
                        },
                        child: Text(store.tr('marketplace.send.request')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
);
  }
}
