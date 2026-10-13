# Android: разрешения

> Актуальная сводка: **[ANDROID.md](./ANDROID.md)**.

Минимум в `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

- Микрофон — при звонке (рантайм).
- Уведомления — при первом запуске / init `flutter_local_notifications` (Android 13+).

Вручную: **Настройки → Приложения → Veniamin → Разрешения**.
