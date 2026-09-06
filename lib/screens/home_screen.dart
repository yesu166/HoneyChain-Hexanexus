import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import 'role_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hexagon_outlined,
                      size: 55,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    store.tr('app.title').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    store.tr('home.tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 35),
                  _Feature(
                    icon: Icons.science_outlined,
                    title: store.tr('feature.lab.title'),
                    text: store.tr('feature.lab.text'),
                  ),
                  const SizedBox(height: 12),
                  _Feature(
                    icon: Icons.account_tree_outlined,
                    title: store.tr('feature.batch.title'),
                    text: store.tr('feature.batch.text'),
                  ),
                  const SizedBox(height: 12),
                  _Feature(
                    icon: Icons.verified_outlined,
                    title: store.tr('feature.record.title'),
                    text: store.tr('feature.record.text'),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RoleScreen()),
                        );
                      },
                      child: Text(
                        store.tr('action.enter'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Feature({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Colors.amber.shade800),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
