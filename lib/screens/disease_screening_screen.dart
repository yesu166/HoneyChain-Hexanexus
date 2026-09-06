import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/disease.dart';
import '../models/domain.dart';
import '../services/disease_detection_service.dart';
import '../services/image_input_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet offering the two photo sources (camera / gallery) plus cancel.
/// Returns `true` for camera, `false` for gallery and `null` for cancel.
Future<bool?> showDiseasePhotoSourceSheet(BuildContext context) {
  final store = HoneyChainStore.instance;
  return showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              store.tr('screening.title'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.photo_camera_outlined,
              color: AppTheme.orangeDark,
            ),
            title: Text(
              store.tr('screening.take.photo'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            subtitle: Text(store.tr('screening.take.photo.note')),
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppTheme.orangeDark,
            ),
            title: Text(
              store.tr('screening.choose.photo'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            subtitle: Text(store.tr('screening.choose.photo.note')),
            onTap: () => Navigator.of(sheetContext).pop(false),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(
                store.tr('action.cancel'),
                style: const TextStyle(color: AppTheme.inkFaint),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Photo-based hive disease screening.
///
/// AI-assisted first-line check: preview the photo, run the analysis through
/// [DiseaseDetectionService], then show one of three qualitative results.
/// The results routine starts with [image]; "Retake" simply re-opens the
/// camera/gallery sheet and the flow converges again.
class DiseaseScreeningScreen extends StatefulWidget {
  const DiseaseScreeningScreen({
    super.key,
    required this.hive,
    required this.image,
  });

  final Hive hive;
  final PickedImage image;

  @override
  State<DiseaseScreeningScreen> createState() => _DiseaseScreeningScreenState();
}

enum _Phase { preview, analyzing, result }

class _DiseaseScreeningScreenState extends State<DiseaseScreeningScreen> {
  late PickedImage _image = widget.image;
  _Phase _phase = _Phase.preview;
  DiseaseScreeningResult? _result;

  Future<void> _pickImage() async {
    final store = HoneyChainStore.instance;
    final source = await showDiseasePhotoSourceSheet(context);
    if (source == null) return;
    try {
      final picked = source
          ? await store.imageInput.pickFromCamera()
          : await store.imageInput.pickFromGallery();
      if (!mounted) return;
      if (picked == null) return;
      setState(() {
        _image = picked;
        _phase = _Phase.preview;
        _result = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('screening.pick.failed'))),
      );
    }
  }

  Future<void> _analyze() async {
    final store = HoneyChainStore.instance;
    setState(() => _phase = _Phase.analyzing);
    try {
      final result = await store.diseaseDetection.screenImage(
        DiseaseImage(bytes: _image.bytes, name: _image.name),
      );
      if (!mounted) return;
      store.recordScreening(widget.hive, result);
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('screening.error.invalid'))),
      );
      setState(() => _phase = _Phase.preview);
    }
  }

  void _done() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('screening.preview.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _PreviewImage(image: _image),
          const SizedBox(height: 14),
          Text(
            widget.hive.detail.isEmpty
                ? widget.hive.name
                : '${widget.hive.name} · ${widget.hive.detail}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          switch (_phase) {
            _Phase.preview => _PreviewControls(
                onAnalyze: _analyze,
                onRetake: _pickImage,
              ),
            _Phase.analyzing => const _AnalyzingState(),
            _Phase.result => _ResultState(
                hive: widget.hive,
                result: _result!,
                onCheckAnother: _pickImage,
                onRetakePhoto: _pickImage,
                onDone: _done,
              ),
          },
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.image});

  final PickedImage image;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppTheme.honey.withValues(alpha: 0.22),
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: image.bytes.isEmpty
          ? const Center(
              child: Icon(
                Icons.image_outlined,
                size: 64,
                color: AppTheme.honeyDark,
              ),
            )
          : Image.memory(
              image.bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 64,
                  color: AppTheme.honeyDark,
                ),
              ),
            ),
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({required this.onAnalyze, required this.onRetake});

  final VoidCallback onAnalyze;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Column(
      children: [
        Text(
          store.tr('screening.photo.ready'),
          style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 8),
        Text(
          store.tr('screening.prototype.note'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppTheme.inkFaint,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.manage_search_rounded, size: 22),
            label: Text(
              store.tr('screening.analyze'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onRetake,
          child: Text(store.tr('screening.retake')),
        ),
      ],
    );
  }
}

class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState();

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppTheme.orangeDark),
          const SizedBox(height: 16),
          Text(
            store.tr('screening.analyzing'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultState extends StatelessWidget {
  const _ResultState({
    required this.hive,
    required this.result,
    required this.onCheckAnother,
    required this.onRetakePhoto,
    required this.onDone,
  });

  final Hive hive;
  final DiseaseScreeningResult result;
  final VoidCallback onCheckAnother;
  final VoidCallback onRetakePhoto;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return switch (result.outcome) {
      DiseaseScreenOutcome.possibleDisease =>
        _PossibleDiseaseResult(result: result, onDone: onDone, onCheckAnother: onCheckAnother),
      DiseaseScreenOutcome.noObviousSigns => _NoneResult(onDone: onDone),
      DiseaseScreenOutcome.unableToAssess => _UnableResult(onRetakePhoto: onRetakePhoto),
    };
  }
}

class _PossibleDiseaseResult extends StatelessWidget {
  const _PossibleDiseaseResult({
    required this.result,
    required this.onCheckAnother,
    required this.onDone,
  });

  final DiseaseScreeningResult result;
  final VoidCallback onCheckAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return _ResultCard(
      accent: AppTheme.orange,
      tint: AppTheme.orangeSoft,
      icon: Icons.warning_amber_rounded,
      title: store.tr('screening.result.possible'),
      children: [
        Text(
          '${store.tr('screening.result.possible.condition')} '
          '${result.condition?.label ?? ''}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 10),
        _Label(store.tr('screening.result.possible.status')),
        Text(
          store.tr('screening.result.possible.further'),
          style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 10),
        _Label(store.tr('screening.result.possible.indicators')),
        for (final item in result.indicators) _Bullet(item),
        const SizedBox(height: 10),
        _Label(store.tr('screening.result.possible.action')),
        for (final item in result.actions) _Bullet(item),
        const SizedBox(height: 8),
        Text(
          store.tr('screening.not.medical'),
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppTheme.inkFaint,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onCheckAnother,
          child: Text(store.tr('screening.check.another')),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.orange),
            child: Text(
              store.tr('screening.done'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoneResult extends StatelessWidget {
  const _NoneResult({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return _ResultCard(
      accent: AppTheme.green,
      tint: AppTheme.greenSoft,
      icon: Icons.check_circle_outline,
      title: store.tr('screening.result.none'),
      children: [
        Text(
          store.tr('screening.result.none.note'),
          style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 10),
        Text(
          store.tr('screening.result.none.reco'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
            child: Text(
              store.tr('screening.done'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnableResult extends StatelessWidget {
  const _UnableResult({required this.onRetakePhoto});

  final VoidCallback onRetakePhoto;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return _ResultCard(
      accent: AppTheme.teal,
      tint: AppTheme.honey.withValues(alpha: 0.18),
      icon: Icons.help_outline_rounded,
      title: store.tr('screening.result.unable'),
      children: [
        Text(
          store.tr('screening.result.unable.note'),
          style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 10),
        Text(
          store.tr('screening.result.unable.reco'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onRetakePhoto,
          child: Text(store.tr('screening.retake.photo')),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.accent,
    required this.tint,
    required this.icon,
    required this.title,
    required this.children,
  });

  final Color accent;
  final Color tint;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: AppTheme.inkFaint,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(
              Icons.circle,
              size: 6,
              color: AppTheme.orangeDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}