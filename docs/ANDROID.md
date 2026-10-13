# Android: сборка и типовые проблемы

Клиент: Flutter (`client/`). Целевые SDK в проекте: **compileSdk / targetSdk 36**.

## Разрешения

Файл: `client/android/app/src/main/AndroidManifest.xml`

Внутри `<manifest>` (до `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

| Разрешение | Зачем |
|------------|--------|
| INTERNET | WebSocket, загрузка медиа |
| RECORD_AUDIO | Голосовые звонки (WebRTC) |
| MODIFY_AUDIO_SETTINGS | Аудиосессия звонка |
| ACCESS_NETWORK_STATE | Состояние сети |
| POST_NOTIFICATIONS | Локальные уведомления (Android 13+) |

Микрофон запрашивается в рантайме при звонке (`permission_handler` / WebRTC).  
Если отказали: **Настройки → Приложения → Veniamin → Разрешения**.

## Core library desugaring

`flutter_local_notifications` требует desugaring в `client/android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36
    // ...
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = 36
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

## file_picker и compileSdk плагинов

Если Gradle ругается, что плагин собран под API 34, а зависимость требует 36, в `client/android/build.gradle.kts` для library-модулей:

```kotlin
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
}
```

Актуальная зависимость в `pubspec.yaml`: `file_picker` (см. файл проекта).

## Галерея vs файлы

- **Файлы** — `file_picker` (любые типы, лимит **25 МБ** на клиенте и сервере).
- **Фото / видео** — `image_picker` (системная галерея).

## Предупреждения KGP (Kotlin Gradle Plugin)

Плагины вроде `file_picker`, `flutter_webrtc` могут писать:

> plugins that apply Kotlin Gradle Plugin (KGP)…

Пока это **warning**. Имеет смысл обновлять плагины по changelog Flutter; на работу debug-сборки обычно не влияет.

## Типовой цикл после правок Gradle / Manifest

```bash
cd client
flutter clean
flutter pub get
flutter run
```

Иконка (если настроен `flutter_launcher_icons`):

```bash
dart run flutter_launcher_icons
```

## Подключение к серверу с телефона

`127.0.0.1` на телефоне — **сам телефон**, не ПК.  
Указывайте **LAN IP** машины с сервером, например `192.168.1.10:8765`.  
Firewall на ПК должен пускать TCP **8765**.
