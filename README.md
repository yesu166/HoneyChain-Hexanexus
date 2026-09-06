# HoneyChain v2

A demo build for Smart India Hackathon giving every honey batch a trusted digital identity:

**Hive → Beekeeper → FPO → Lab → Processing → Verified Marketplace → Consumer**

This is a local/offline demo. All data is deterministic mock data. There is **no** dependence on
physical IoT hardware, a live blockchain, an external AI API, or the internet.

## New in this build

- **First-launch role gate ("WHO ARE YOU?")** — the app opens with a two-option gate
  (`lib/screens/who_are_you_screen.dart`): tap **Beekeeper** to enter the existing phone + OTP
  login and portal, or **Organization / FPO** to open the lightweight org sign-in. The app
  returns to this gate after any logout.
- **Organization / FPO portal** (`lib/screens/org/`) — a distinct entry for the cooperative body:
  select the active org from the seeded list, enter a name, and continue into a dedicated org
  dashboard with collection, batch creation, product/QR passport, and batch detail screens. Uses
  the same cream/orange/green theme (not a separate blue admin UI).
- **Bee health symptom illustration** (`lib/bee_health/widgets/symptom_illustration.dart`) — each
  of the 8 YES / NO / NOT SURE questions now shows a matching `CustomPaint` icon above the answers
  and a "QUESTION X OF 8" pill. The ML feature order and encoding are unchanged.
- **Speech-to-text mic detection** (`lib/services/speech/`) — the web voices/speech feature now
  reads `webkitSpeechRecognition` / `SpeechRecognition` off the global context via strict
  `dart:js_interop` + `dart:js_interop_unsafe`, with graceful fallback when the browser is
  unsupported.
- **Runtime-robust data layer** — the `productBatches` getter returns a defensive copy before
  sorting (fixes "Unsupported operation: sort"), and empty harvest/reading lists are guarded so
  the UI shows "No reading" / "Honey" instead of crashing.

## Three pillars

1. **Produce smarter** — historical/IoT hive readings (temperature, humidity, weight, trend)
   produce a health score, risk level, productivity insight, and inspection recommendation.
   These are *risk predictions*, not disease diagnoses.
2. **Prove & trace** — harvest → batch → lab verification → blockchain anchor (mock) →
   custody → genealogy → QR Honey Passport.
3. **Sell better** — verified batches go to a marketplace where buyers can request purchase.
   No payments, logistics, or carts.

## Roles

- **Beekeeper**: dashboard, hive health, risk insight, record harvest, harvest history.
- **FPO / Collection Center**: harvests, create batch, custody, verification, traceability, marketplace, QR.
- **Laboratory**: verify batches (PASS / FAIL).
- **Processor**: custody, processing, split/aggregate genealogy.
- **Consumer**: enter/simulate a QR scan → Honey Passport (origin, harvest, lab, custody, blockchain, status).
- **Regulator / Admin**: batch + audit view.

## Architecture

```
lib/
  models/       typed domain models (v2)
  data/         local repository + deterministic demo seed
  repositories/ local/mock implementation of the data boundaries
  services/     hive insight, batch, verification, custody, blockchain,
                genealogy, passport, marketplace, speech
  screens/      presentation layer (incl. org/ portal, who-are-you gate)
  bee_health/   symptom questions, illustration + result screens
  widgets/      reusable presentation components
  theme/        shared cream/orange/green theme
```

The presentation layer is separated from services and data so a future Figma-generated UI can
replace the screens without changing the business logic, models, or services.

Blockchain is intentionally present as **prototype/mock infrastructure** — it preserves record
integrity and does **not** detect counterfeit honey.

## Running

- `flutter analyze`
- `flutter test` (all tests pass, including the updated gate-flow and logout tests)
- `flutter run` (any enabled device)
- `flutter build web` for a web bundle
- `flutter build apk --release` for an Android APK

## Android build notes

Latest build reaches the Gradle `assembleRelease` target (the duplicate-Kotlin "Redeclaration"
issue in the Flutter SDK tooling is fixed by removing the `(1).kt` copies). The remaining blocker
is a network resolution error downloading a Gradle dependency
(`No such host is known: dl.google.com`), i.e. connectivity during dependency fetch, not an app
code problem. Retry with a live connection, or open the project in Android Studio (`android/`) to
build the APK there.