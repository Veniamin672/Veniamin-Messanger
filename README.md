# Veniamin

Закрытый групповой мессенджер (~10 человек) в стиле терминала / IDE.

- **Клиент**: Flutter (Windows, Android, iOS)
- **Сервер**: Python 3.10+ (asyncio + websockets)
- **Протокол**: JSON-пакеты по WebSocket
- **Идентификация**: UUID устройства (генерируется и сохраняется локально)
- **Админ**: первый пользователь становится админом, принимает/отклоняет новых
- **Голосовые звонки**: WebRTC (flutter_webrtc), сигналинг через сервер
- **Авто-удаление**:
  - текстовые сообщения — через 7 дней
  - файлы и фото — через 3 дня
  - видео — на следующий день
  - очистка каждый день в **03:00** (локальное время сервера)
- **Подключение**: Пока что для подключения нужен посторонний VPN как TailScale

---

## Структура

```
veniamin/
├── server/                 # Python-сервер
│   ├── server.py           # точка входа
│   ├── config.py
│   ├── protocol.py
│   ├── storage.py
│   ├── generate_certs.py
│   ├── reset_data.py       # полный сброс всех данных через удаление папки data/
│   ├── requirements.txt
│   ├── run.sh
│   ├── run.bat            # запуск сервера
│   ├── generate_certs.sh
│   └── generate_certs.bat # получение сертификата WSS, обязательно запустить перед первым запуском сервера если WSS включён
├── client/                 # Flutter-клиент
│   ├── lib/
│   │   ├── main.dart
│   │   ├── theme.dart
│   │   ├── services/
│   │   │   ├── connection.dart
│   │   │   ├── device_id.dart
│   │   │   ├── local_labels.dart
│   │   │   └── device_id.dart
│   │   └── screens/
│   │       ├── connect_screen.dart
│   │       ├── chat_screen.dart
│   │       ├── admin_panel.dart
│   │       └── call_screen.dart
│   └── pubspec.yaml
└── docs/
    ├── README.md
    ├── SETUP.md
    ├── protocol.md
    ├── ANDROID.md
    ├── ANDROID_FILE_PICKER_FIX.md
    ├── ANDROID_FIX.md
    └── ANDROID_PERMISSIONS.md
```

---

## Запуск сервера

Перед первым запуском стоит запустить `generate_certs.bat` на Windows и `generate_certs.sh` на Linux для создания сертификатов WSS. WSS можно отключить в `server/config.py`, тогда сертификаты становятся необязательными.

```bash
cd server
python -m venv venv

# Windows:
venv\Scripts\activate

# Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt
python server.py
```


Или файлом run.bat на Windows и run.sh на Linux

Сервер слушает `0.0.0.0:8765` (настраивается в `config.py`).

Данные хранятся в `server/data/`:
- `users.json` — одобренные пользователи
- `pending.json` — заявки на вход
- `admin_uuid.txt` — UUID админа
- `messages/YYYY-MM-DD.jsonl` — сообщения
- `media/` — файлы

**Первый подключившийся и отправивший `auth` автоматически становится админом.**

---

## Запуск клиента для разработчиков (Flutter)

Требуется Flutter SDK ≥ 3.16.

```bash
cd client
flutter pub get
flutter run -d windows    # или android / ios / macos
```

## Запуск клиента для пользователей

На телефоне:
В папке `Output` скачиваете и запускаете файл `app-release.apk` на телефоне который находится в релизах

На Windows/Linux:
В папке `Output` скачиваете и запускаете файл `veniamin_setup.exe` на компьютере который находится в релизах

### Первый экран

1. Поле **server IP / host**
   (Что бы узнать свой IP сервера на Windows в консольной строке пишете:
```bash
ipconfig
```
И в Wireless `LAN adapter WiFi:` найдите `IPv4 Address`, там и будет указан ваш ip
На Linux:
```bash
hostname -I
```
)
2. **port** (по умолчанию 8765, но можно изменить в `server/config.py`)
3. **WSS** функция защиты передачи пакетов от посредника, включить или выключить в зависимости от настроек сервера указанных в `server/config.py`
3. **display name**
4. Отображается **device_uuid** (можно скопировать)
5. Отображается **account_id** (также можно скопировать, нужен для смены аккаунта)
5. Кнопка `> connect`

После подключения:
- если UUID уже одобрен → сразу в чат
- если новый → заявка уходит админу, статус `waiting for admin approval`
- админ в панели принимает/отклоняет

---

## Протокол (кратко)

Все пакеты — JSON с полем `type`.

| type (client→server) | Описание |
|----------------------|----------|
| `hello` | handshake + device_uuid |
| `auth` | запрос доступа |
| `message` | текстовое сообщение |
| `file` | файл/фото/видео (base64) |
| `call_offer` / `call_answer` / `call_ice` / `call_hangup` | WebRTC signaling |
| `admin_accept` / `admin_reject` / `admin_kick` | только админ |
| `get_history` / `get_users` | история и список |

| type (server→client) | Описание |
|----------------------|----------|
| `auth_accepted` / `auth_pending` / `auth_rejected` | результат авторизации |
| `message_broadcast` / `file_broadcast` | новое сообщение |
| `history` / `user_list` / `pending_list` | данные |
| `call_incoming` / `call_answered` / `call_ice_candidate` / `call_ended` | звонки |

Подробнее: `docs/protocol.md`.
Пока устаревший, были добавлены новые типы пакетов.

---

## Голосовые звонки

1. Пользователь нажимает иконку звонка рядом с онлайн-пользователем.
2. Клиент создаёт WebRTC PeerConnection (только audio, пока что).
3. SDP offer / answer / ICE передаются через сервер JSON-пакетами.
4. STUN: `stun:stun.l.google.com:19302` (для NAT).
5. Для сложных NAT может понадобиться свой TURN-сервер.

---

## Безопасность (текущее состояние)

- Это **закрытый** мессенджер по IP, без публичной регистрации.
- Нет end-to-end шифрования (сообщения на сервере в открытом виде).
- Нет TLS — для продакшена рекомендуется reverse-proxy (nginx + wss) или cert.
- UUID устройства — единственный идентификатор; при компрометации устройства админ может кикнуть.

Для усиления можно добавить:
- pre-shared group key + E2E
- PIN/код приглашения
- TLS (wss)

---

## Дальнейшие шаги

- [ ] Chunked upload больших файлов
- [ ] Push-уведомления (FCM / APNs)
- [ ] Локальное хранение истории на клиенте
- [ ] Групповые звонки (SFU)
- [ ] Закрепление сообщений для сохранения на большее количество времени
- [ ] Демонстрация экрана в звонке
- [ ] Веб-камера в звонке

---

**Veniamin** — сделано для небольшой закрытой группы.

---

## Раздача друзьям для разработчиков(сборки)

### Windows
```bash
cd client
flutter build windows --release
```
Готовый exe: `build/windows/x64/runner/Release/`

Можно заархивировать всю папку Release и отправить. Либо сделать инсталлятор через [Inno Setup](https://jrsoftware.org/isinfo.php).

### Android (APK)
```bash
flutter build apk --release
```
Файл: `build/app/outputs/flutter-apk/app-release.apk`  
Друзья ставят APK (нужно разрешить установку из неизвестных источников).

### Android (App Bundle для Play Store)
```bash
flutter build appbundle --release
```

### iOS
Нужен Mac + Apple Developer аккаунт:
```bash
flutter build ipa --release
```

### Сервер друзьям
Отправь папку `server/` + Python 3.10+.  
Они запускают `run.bat` / `run.sh`, открывают порт 8765 в роутере/файрволе, дают тебе/друзьям свой публичный IP.

---

## Новое в v1.1
- Группы (создание всем, add/remove участников; админа сервера нельзя удалить)
- Отправка и скачивание файлов
- Admin: system broadcast всем
- Admin: полный сброс сообщений (пароль `3648` можно настроить через server/config.py)
- Тема: #1E1E1E / #252526 / #007c42 / #D4D4D4 / #808080

## Новое в v1.2
- Таймер звонка
- Mesh(групповой звонок)
- Настройки вывода звука звонка
- WSS соединение(защита передачи пакетов от посредника)
