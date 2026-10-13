# Android permissions for voice calls

В `client/android/app/src/main/AndroidManifest.xml` внутри `<manifest>` добавь:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

Без `RECORD_AUDIO` микрофон на телефоне не откроется и звонок «вечно connecting».
