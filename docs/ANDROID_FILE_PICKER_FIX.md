# Android: file_picker и compileSdk 36

> Актуальная сводка: **[ANDROID.md](./ANDROID.md)**.

Если `:file_picker:checkDebugAarMetadata` требует API ≥ 36, а плагин собран под 34, в `client/android/build.gradle.kts`:

```kotlin
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
}
```

В `app/build.gradle.kts` уже должно быть `compileSdk = 36`.

```bash
flutter clean
flutter pub get
flutter run
```

Версию `file_picker` смотрите в `client/pubspec.yaml`.
