# clarix

A simple local Gemma chat app built with Flutter and `flutter_gemma`.

## Local model setup

The app loads the model from the filesystem, not from the Flutter asset bundle.

- Model path: `assets/models/gemma-4-E2B-it.litertlm`
- Loading method: `FlutterGemma.installModel(...).fromFile(...)`
- Speculative decoding: enabled for Gemma 4

## Run it

```bash
flutter pub get
flutter run
```

If you rename or move the model file, update the path in `lib/main.dart`.
