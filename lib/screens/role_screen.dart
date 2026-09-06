import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import 'beekeeper_screen.dart';
import 'consumer_screen.dart';
import 'fpo_screen.dart';
import 'lab_screen.dart';
import 'regulator_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('role.choose.title'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            store.tr('role.choose.heading'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            store.tr('role.choose.subtitle'),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 25),

          _RoleCard(
            emoji: '🐝',
            title: store.tr('role.beekeeper'),
            subtitle: store.tr('role.beekeeper.desc.short'),
            onTap: () => _open(context, const BeekeeperScreen()),
          ),
          _RoleCard(
            emoji: '📦',
            title: store.tr('role.collection'),
            subtitle: store.tr('role.collection.desc'),
            onTap: () => _open(context, const FpoScreen()),
          ),
          _RoleCard(
            emoji: '🧪',
            title: store.tr('role.lab'),
            subtitle: store.tr('role.lab.desc'),
            onTap: () => _open(context, const LabScreen()),
          ),
          _RoleCard(
            emoji: '👤',
            title: store.tr('role.consumer'),
            subtitle: store.tr('role.consumer.desc'),
            onTap: () => _open(context, const ConsumerScreen()),
          ),
          _RoleCard(
            emoji: '🛡️',
            title: store.tr('role.regulator'),
            subtitle: store.tr('role.regulator.desc'),
            onTap: () => _open(context, const RegulatorScreen()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Text(emoji, style: const TextStyle(fontSize: 30)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 17),
        onTap: onTap,
      ),
    );
  }
}
