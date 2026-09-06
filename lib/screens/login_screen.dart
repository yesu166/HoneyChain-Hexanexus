import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/honeychain_store.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _otp = List.generate(4, (_) => TextEditingController());
  final _otpFocus = List.generate(4, (_) => FocusNode());

  bool _validPhone = false;
  bool _validOtp = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phone.addListener(() {
      final valid =
          _phone.text.length == 10 && RegExp(r'^[0-9]+$').hasMatch(_phone.text);
      if (valid != _validPhone) setState(() => _validPhone = valid);
    });
    for (var i = 0; i < 4; i++) {
      final index = i;
      _otp[i].addListener(() {
        final filled = _otp.every(
            (c) => c.text.isNotEmpty && RegExp(r'^[0-9]$').hasMatch(c.text));
        if (filled != _validOtp) setState(() => _validOtp = filled);
        if (_otp[index].text.isNotEmpty && index < 3) {
          _otpFocus[index + 1].requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    for (var i = 0; i < 4; i++) {
      _otp[i].dispose();
      _otpFocus[i].dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final store = HoneyChainStore.instance;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    store.completeLogin(
      phone: '+91 ${_phone.text}',
      name: store.profile.name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.orange, width: 2),
                  color: AppTheme.card,
                ),
                child: const Icon(
                  Icons.hive_outlined,
                  size: 34,
                  color: AppTheme.orangeDark,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'HoneyChain',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              store.tr('app.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 30),
            SectionLabel(store.tr('select.language')),
            _LanguageSelector(),
            const SizedBox(height: 26),
            SectionLabel(store.tr('phone.label')),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
              decoration: InputDecoration(
                hintText: '9876543210',
                prefixText: '+91 ',
                filled: true,
                fillColor: AppTheme.card,
                hintStyle: const TextStyle(
                  color: AppTheme.inkFaint,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
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
                  borderSide: const BorderSide(
                    color: AppTheme.orange,
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(store.tr('otp.label')),
            Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 60,
                    margin: EdgeInsets.only(right: i < 3 ? 12 : 0),
                    child: TextField(
                      controller: _otp[i],
                      focusNode: _otpFocus[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.card,
                        contentPadding: EdgeInsets.zero,
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
                          borderSide: const BorderSide(
                            color: AppTheme.orange,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              store.tr('demo.otp'),
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _validPhone && _validOtp && !_busy ? _verify : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  disabledBackgroundColor: AppTheme.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  store.tr('verify.login'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final current = store.language;
        return Row(
          children: [
            for (final lang in AppLanguages.all) ...[
              Expanded(
                child: _LangCard(
                  lang: lang,
                  selected: lang.code == current,
                  onTap: () => store.setLanguage(lang.code),
                ),
              ),
              if (lang != AppLanguages.all.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: selected ? AppTheme.orangeSoft : AppTheme.card,
          borderRadius: AppTheme.radiusField,
          border: Border.all(
            color: selected ? AppTheme.orange : AppTheme.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          lang.nativeName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: selected ? AppTheme.ink : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}