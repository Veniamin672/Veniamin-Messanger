# Android: compileSdk / targetSdk

> Актуальная сводка: **[ANDROID.md](./ANDROID.md)**.  
> Этот файл сохранён как короткий чеклист.

В `client/android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36
    defaultConfig {
        targetSdk = 36
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

```bash
flutter clean && flutter pub get && flutter run
```
