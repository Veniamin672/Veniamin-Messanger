# Установка и запуск Veniamin

## Требования

| Компонент | Требование |
|-----------|------------|
| Сервер | Python **3.10+** |
| Клиент | Flutter **stable** (3.22+ желательно) |
| Сеть | Клиенты достучатся до `HOST:8765` (LAN / VPN / port-forward) |

Репозиторий:

```text
veniamin/
  server/     # Python asyncio WebSocket
  client/     # Flutter (Windows / Android / iOS)
  docs/       # документация
```

---

## Сервер

```bash
cd server
python -m venv .venv

# Windows
.venv\Scripts\activate
# Linux / macOS
source .venv/bin/activate

pip install -r requirements.txt
python server.py
# или: run.bat / run.sh
```

Слушает **`0.0.0.0:8765`** (`config.py`).

### Данные

Каталог `server/data/` (создаётся сам):

| Путь | Содержимое |
|------|------------|
| `users.json` | Устройства и account_id |
| `groups.json` | Группы и members (account_id) |
| `pending.json` | Заявки на вход |
| `admin_uuid.txt` | Первичный admin device |
| `messages/*.jsonl` | История по дням |
| `media/` | Вложения |

### Полный сброс

```bash
cd server
python reset_data.py
python server.py
```

Первый подключившийся клиент снова становится админом.  
На клиентах лучше **Disconnect** и при необходимости новый account_id.

### Пароль сброса сообщений (админ-панель)

По умолчанию: **`4593`** (`ADMIN_RESET_PASSWORD` в `config.py`).  
**Смените перед публичным деплоем.**

---

## Клиент (Flutter)

```bash
cd client
flutter pub get
flutter run -d windows    # или android / подключённый девайс
```

### Первый вход

1. Display name  
2. IP сервера (с телефона — **не** `127.0.0.1`, а LAN IP ПК)  
3. Порт `8765`  
4. Опционально **account_id** — тот же, что на другом устройстве, чтобы связать аккаунт  

Первый пользователь = **admin** (одобряет остальных в админ-панели).

### Автоподключение

После успешного входа хост/порт/имя сохраняются.  
Пока не нажали **Disconnect**, при открытии приложения клиент пытается переподключиться.

### Сборка APK (пример)

```bash
cd client
flutter build apk --release
# артефакт: build/app/outputs/flutter-apk/app-release.apk
```

Для release нужна своя signing-конфигурация (сейчас в debug часто debug-keys).

### iOS

Сборка IPA — с **Mac + Xcode**.  
Код клиента общий; настройте team/signing в `ios/`.  
Подробности: [Flutter iOS deploy](https://docs.flutter.dev/deployment/ios).

---

## Возможности клиента (кратко)

- Тёмный UI (терминал / IDE): палитра `#1E1E1E`, `#252526`, акцент `#007c42`
- Чаты по группам, «Общий»
- Файлы / галерея, превью фото·аудио·видео, лимит 25 МБ
- Ответ, редактирование своих, удаление (свои / админ — любые)
- WebRTC-голос, шторка входящего, «линия занята»
- Локальные подписи людей и групп (только на устройстве)
- Локальные уведомления, пока процесс жив и сокет подключён

---

## Безопасность (важно для GitHub / продакшена)

- Нет TLS и нет E2E: трафик и сервер видят сообщения и файлы.
- Используйте только **доверенную** сеть или свой VPN / reverse-proxy с TLS.
- Смените `ADMIN_RESET_PASSWORD`, не коммитьте `server/data/` с реальной перепиской.
- Рекомендуется добавить `server/data/` в `.gitignore`.
