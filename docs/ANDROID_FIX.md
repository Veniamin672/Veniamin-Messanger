# Исправление Android compileSdk

В `client/android/app/build.gradle.kts` замени строку:

```kotlin
compileSdk = flutter.compileSdkVersion
```

на:

```kotlin
compileSdk = 36
```

Можно также явно задать targetSdk:

```kotlin
defaultConfig {
    applicationId = "com.example.veniamin"
    minSdk = flutter.minSdkVersion
    targetSdk = 36
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

Полный блок `android { ... }` после правки:

```kotlin
android {
    namespace = "com.example.veniamin"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.veniamin"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
```

Затем:

```bash
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter run
```
