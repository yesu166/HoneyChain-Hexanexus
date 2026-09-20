import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_config.dart';
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
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _showPassword = false;

  bool _validPhone = false;
  bool _validOtp = false;
  bool _busy = false;
  bool _busyBackend = false;
  String? _backendError;

  bool get _backendEnabled =>
      ApiConfig.isConfigured && !HoneyChainStore.testMode;

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
    _identifier.dispose();
    _password.dispose();
    _passwordFocus.dispose();
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

  Future<void> _verifyBackend() async {
    final store = HoneyChainStore.instance;
    setState(() {
      _busyBackend = true;
      _backendError = null;
    });
    final role = await store.beekeeperLogin(
      identifier: _identifier.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busyBackend = false;
      if (role == null) {
        _backendError =
            store.backendError ?? store.serverCollectionsError ?? 'Sign-in failed';
      }
    });
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
                  border: Border.all(color: AppTheme.honeyGold, width: 2),
                  color: AppTheme.card,
                ),
                child: const Icon(
                  Icons.hive_outlined,
                  size: 34,
                  color: AppTheme.honeyDark,
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
            if (_backendEnabled) ...[
              const SizedBox(height: 26),
              Text(store.tr('login.beekeeper.signin'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.ink)),
              _BackendSignInForm(
                identifier: _identifier,
                password: _password,
                passwordFocus: _passwordFocus,
                busy: _busyBackend,
                error: _backendError,
                onSignIn: _verifyBackend,
              ),
            ] else ...[
            if (HoneyChainStore.testMode) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => store.completeLogin(
                    phone: '',
                    name: store.profile.name.trim().isEmpty ? 'Beekeeper' : store.profile.name.trim(),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: Text(store.tr('login.continue.beekeeper'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                store.tr('login.local.test'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.inkFaint),
              ),
            ],
            const SizedBox(height: 20),
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
                    color: AppTheme.honeyGold,
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
                            color: AppTheme.honeyGold,
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
                  backgroundColor: AppTheme.honeyGold,
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
                          color: AppTheme.ink,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 20,
                        color: AppTheme.ink),
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
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final lang in AppLanguages.all)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 58) / 2,
                child: _LangCard(
                  lang: lang,
                  selected: lang.code == current,
                  onTap: () => store.setLanguage(lang.code),
                ),
              ),
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
          color: selected ? const Color(0x1FE8A33D) : AppTheme.card,
          borderRadius: AppTheme.radiusField,
          border: Border.all(
            color: selected ? AppTheme.honeyGold : AppTheme.border,
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

/// Email/phone + password sign-in against the live FastAPI backend. Shown only
/// when a backend URL is compiled in (see [ApiConfig]); the demo OTP flow stays
/// the fallback for offline/untargeted builds.
class _BackendSignInForm extends StatefulWidget {
  const _BackendSignInForm({
    required this.identifier,
    required this.password,
    required this.passwordFocus,
    required this.busy,
    required this.error,
    required this.onSignIn,
  });

  final TextEditingController identifier;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final bool busy;
  final String? error;
  final VoidCallback onSignIn;

  @override
  State<_BackendSignInForm> createState() => _BackendSignInFormState();
}

class _BackendSignInFormState extends State<_BackendSignInForm> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final identifier = widget.identifier;
    final password = widget.password;
    final passwordFocus = widget.passwordFocus;
    final busy = widget.busy;
    final error = widget.error;
    final onSignIn = widget.onSignIn;
    return Column(
      children: [
        TextField(
          controller: identifier,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
          decoration: InputDecoration(
            hintText: 'Email or phone number',
            prefixIcon: const Icon(Icons.mail_outline,
                color: AppTheme.inkFaint, size: 20),
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
                color: AppTheme.honeyGold,
                width: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          focusNode: passwordFocus,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => busy ? null : onSignIn(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
          decoration: InputDecoration(
            hintText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppTheme.inkFaint, size: 20),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppTheme.inkFaint,
              ),
            ),
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
                color: AppTheme.honeyGold,
                width: 1.6,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: busy ? null : onSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.honeyGold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.ink,
                    ),
                  )
                : const Icon(Icons.cloud_done_outlined, size: 20,
                    color: AppTheme.ink),
            label: Text(
              busy ? 'Signing in…' : 'Sign in',
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