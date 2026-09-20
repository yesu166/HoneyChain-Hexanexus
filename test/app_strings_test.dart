import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/l10n/app_strings.dart';

void main() {
  const requiredLanguages = ['en', 'hi', 'bn', 'pa', 'ta', 'ml', 'mr'];

  const coreKeys = [
    'app.subtitle',
    'nav.home',
    'nav.hives',
    'nav.honey',
    'nav.alerts',
    'nav.profile',
    'nav.more',
    'home.quick.actions',
    'home.greeting.morning',
    'home.greeting.afternoon',
    'home.greeting.evening',
    'home.hives.metric',
    'home.healthy.metric',
    'home.attention.metric',
    'status.online',
    'status.offline',
    'record.harvest.title',
    'record.harvest.save',
    'bh.title',
    'bh.result.confirmation',
    'screening.title',
    'screening.analyze',
    'screening.not.medical',
    'profile.producer.label',
    'prompt.language',
    'action.cancel',
    'action.confirm',
  ];

  test('HoneyChain exposes exactly the seven supported languages', () {
    expect(AppLanguages.all.map((e) => e.code), requiredLanguages);
  });

  test('all language selector labels are native and unique', () {
    final codes = AppLanguages.all.map((e) => e.code).toSet();
    final nativeNames = AppLanguages.all.map((e) => e.nativeName).toSet();
    expect(codes.length, requiredLanguages.length);
    expect(nativeNames.length, requiredLanguages.length);
    expect(AppLanguages.all.map((e) => e.nativeName), [
      'English',
      'हिन्दी',
      'বাংলা',
      'ਪੰਜਾਬੀ',
      'தமிழ்',
      'മലയാളം',
      'मराठी',
    ]);
  });

  test('core UI strings are translated for every supported language', () {
    for (final language in requiredLanguages) {
      for (final key in coreKeys) {
        final localized = AppStrings.of(language, key);
        expect(localized, isNot(key), reason: '$language is missing $key');
        if (language != 'en') {
          expect(
            localized,
            isNot(AppStrings.of('en', key)),
            reason: '$language still falls back to English for $key',
          );
        }
      }
    }
  });

  test('localized placeholders remain intact', () {
    const placeholders = {
      'home.greeting.morning': ['{name}'],
      'home.greeting.afternoon': ['{name}'],
      'home.greeting.evening': ['{name}'],
      'home.all.healthy': ['{count}'],
      'home.my.hives.sub': ['{count}', '{healthy}'],
      'time.minutes.ago': ['{n}'],
      'time.hours.ago': ['{n}'],
      'time.days.ago': ['{n}'],
    };

    for (final language in requiredLanguages) {
      for (final entry in placeholders.entries) {
        final value = AppStrings.of(language, entry.key);
        for (final token in entry.value) {
          expect(value, contains(token), reason: '$language lost $token in ${entry.key}');
        }
      }
    }
  });
}
