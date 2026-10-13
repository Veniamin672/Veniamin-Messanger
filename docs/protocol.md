# Veniamin Protocol v1.1

Транспорт: **WebSocket**, текстовые кадры, UTF-8 JSON.  
Порт по умолчанию: **8765**. TLS/E2E в текущей версии **нет** — рассчитано на доверенную локальную сеть.

Каждый пакет:

```json
{
  "type": "<string>",
  "ts": 1710000000000,
  "id": "<uuid>",
  "...": "поля по типу"
}
```

| Поле | Описание |
|------|----------|
| `type` | Тип пакета (обязательно) |
| `ts` | Unix time в **миллисекундах** (сервер/клиент) |
| `id` | UUID пакета (генерирует отправитель) |

Идентичность:

- **`device_uuid`** — ID устройства (сессия, сокет, WebRTC).
- **`account_id`** — ID аккаунта (группы, права, отображение «человека»).  
  Группы и членство хранятся **только по `account_id`**.

---

## 1. Handshake

### Client → Server: `hello`

```json
{
  "type": "hello",
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "display_name": "Normas",
  "account_id": "optional-existing-or-new-account-uuid",
  "device_info": { "platform": "android" },
  "protocol": "1.1"
}
```

| Поле | Описание |
|------|----------|
| `device_uuid` | Постоянный UUID устройства (клиент создаёт и хранит) |
| `account_id` | Если задан и известен серверу — устройство привязывается к этому аккаунту |
| `device_info.platform` | `windows` / `android` / `ios` / … |

### Server → Client

**Уже одобрен** → `auth_accepted`:

```json
{
  "type": "auth_accepted",
  "user": {
    "uuid": "<device_uuid>",
    "account_id": "<account_id>",
    "display_name": "Normas",
    "role": "admin",
    "joined_at": 1710000000000
  },
  "is_admin": true,
  "users": [ /* агрегированные аккаунты */ ],
  "groups": [ /* только группы этого account_id */ ]
}
```

**В очереди** → `{ "type": "auth_pending" }`

**Новое устройство** → `{ "type": "auth_required" }` — клиент шлёт `auth`.

**Отклонён** → `{ "type": "auth_rejected" }`

---

## 2. Авторизация

### Client → Server: `auth`

```json
{
  "type": "auth",
  "display_name": "Bob",
  "account_id": "optional",
  "device_info": { "platform": "windows" }
}
```

- **Первый** пользователь на сервере → автоматически **admin** + `auth_accepted`.
- Иначе → `pending`, клиенту `auth_pending`.

### Admin: `admin_accept` / `admin_reject`

```json
{ "type": "admin_accept", "uuid": "<device_uuid>" }
{ "type": "admin_reject", "uuid": "<device_uuid>" }
```

После accept целевой клиент (если онлайн) получает `auth_accepted`.

### Admin: `admin_list_pending`

```json
{ "type": "admin_list_pending" }
→ { "type": "pending_list", "pending": [ { "uuid", "display_name", "requested_at", ... } ] }
```

### Admin: `admin_kick`

```json
{ "type": "admin_kick", "uuid": "<device_or_account_id>" }
```

Удаляет устройство/аккаунт и вычищает из групп.

---

## 3. Пользователи (аккаунты)

Список пользователей — **агрегация по `account_id`**:

```json
{
  "type": "user_list",
  "users": [
    {
      "uuid": "<account_id>",
      "account_id": "<account_id>",
      "display_name": "Normas",
      "role": "admin",
      "online": true,
      "platforms": ["windows", "android"],
      "device_uuids": ["…", "…"],
      "call_device_uuid": "<device to ring>"
    }
  ]
}
```

Клиент: `{ "type": "get_users" }`.  
События: `user_joined`, `user_left` (часто с `account_id` / `uuid`).

---

## 4. Группы

Членство = список **`account_id`**.  
Группа **`global`** («Общий») — все аккаунты сервера; состав вручную не меняется.

### Запрос списка

```json
{ "type": "get_groups" }
→ {
  "type": "group_list",
  "groups": [
    {
      "id": "global",
      "name": "Общий",
      "owner_uuid": null,
      "members": ["acc1", "acc2"],
      "member_count": 2,
      "created_at": 1710000000000
    }
  ]
}
```

Клиент видит **только** группы, где он в `members`.

### Создать

```json
{ "type": "create_group", "name": "Ночная" }
```

Владелец (`owner_uuid` = account_id) сразу единственный участник.

### Добавить / удалить / выйти

```json
{ "type": "add_to_group", "group_id": "…", "member_uuid": "<account_id>" }
{ "type": "remove_from_group", "group_id": "…", "member_uuid": "<account_id>" }
{ "type": "leave_group", "group_id": "…" }
```

Серверный **admin** нельзя выгнать из группы другими (сам выйти может, кроме логики global).

События: `group_updated`, повторная `group_list`.

---

## 5. Сообщения

### Текст

```json
{
  "type": "message",
  "text": "привет",
  "group_id": "global",
  "reply_to": {
    "id": "<message_id>",
    "from_name": "Alice",
    "text": "цитата…",
    "msg_type": "text"
  }
}
```

`reply_to` опционален.

### Broadcast

```json
{
  "type": "message_broadcast",
  "id": "…",
  "from_uuid": "<device>",
  "from_name": "Alice",
  "group_id": "global",
  "msg_type": "text",
  "text": "привет",
  "reply_to": { … },
  "edited": false,
  "ts": 1710000000000
}
```

### Редактирование (только автор, не админ за чужих)

```json
{ "type": "edit_message", "message_id": "…", "text": "новый текст" }
→ {
  "type": "message_edited",
  "message_id": "…",
  "text": "новый текст",
  "edited": true,
  "edited_ts": 1710000001000,
  "group_id": "…"
}
```

### Удаление

```json
{ "type": "delete_message", "message_id": "…" }
```

- Автор — свои.  
- Admin — любые (включая system/date по правилам сервера).

```json
{ "type": "message_deleted", "message_id": "…", "media_id": "optional" }
```

### Файл

Лимит: **25 МБ** сырых данных.

```json
{
  "type": "file",
  "filename": "photo.jpg",
  "mime": "image/jpeg",
  "size": 12345,
  "data": "<base64>",
  "group_id": "global"
}
```

```json
{
  "type": "file_broadcast",
  "id": "…",
  "from_uuid": "…",
  "from_name": "Alice",
  "group_id": "global",
  "msg_type": "file",
  "media_id": "…",
  "filename": "photo.jpg",
  "mime": "image/jpeg",
  "size": 12345,
  "ts": …
}
```

Тело файла в broadcast **не** передаётся.

### Скачать медиа

```json
{ "type": "get_media", "media_id": "…" }
→ { "type": "media_data", "media_id": "…", "data": "<base64>", "mime": "…", "filename": "…" }
```

### История

```json
{ "type": "get_history", "group_id": "global", "limit": 100, "before_ts": null }
→ { "type": "history", "group_id": "global", "messages": [ … ] }
```

---

## 6. Админ-рассылки и сброс

```json
{ "type": "admin_broadcast", "text": "Внимание всем" }
```

Уходит **во все группы** как system/broadcast-сообщение.

```json
{ "type": "admin_reset_messages", "password": "4593" }
→ { "type": "reset_done" }
```

Пароль задаётся в `server/config.py` (`ADMIN_RESET_PASSWORD`).

---

## 7. Системные сообщения

- Разделитель даты около **00:00** серверного времени: текст вида `--- DD/MM/YYYY ---`, `msg_type`: `date` / system.
- `system` / `system_broadcast` — служебные строки.

---

## 8. Голосовые звонки (WebRTC signaling)

Сигналинг через сервер; медиа — P2P (STUN).

| Клиент | Сервер |
|--------|--------|
| `call_offer` | `call_incoming` |
| `call_answer` | `call_answered` |
| `call_ice` | `call_ice_candidate` |
| `call_hangup` / `call_reject` | `call_ended` |

```json
{
  "type": "call_offer",
  "to_uuid": "<account_or_device>",
  "call_id": "…",
  "sdp": { "type": "offer", "sdp": "…" }
}
```

**Занятость линии:** если аккаунт уже в звонке / на гудках:

```json
{
  "type": "call_busy",
  "to_uuid": "…",
  "call_id": "…",
  "message": "Линия этого абонента занята, попробуйте перезвонить позже"
}
```

Звонок на тот же `account_id` (своё второе устройство) сервером отсекается.

---

## 9. Прочее

```json
{ "type": "ping" } → { "type": "pong" }
{ "type": "typing", "group_id": "…", "is_typing": true }
→ { "type": "typing_broadcast", "uuid": "…", "display_name": "…", "group_id": "…", "is_typing": true }
{ "type": "read", "message_id": "…" } → { "type": "read_receipt", … }
{ "type": "error", "message": "…" }
```

---

## 10. Retention (сервер)

Очистка **ежедневно в 03:00** (локальное время сервера):

| Тип | Срок |
|-----|------|
| Текстовые сообщения | 7 суток |
| Файлы / фото | 3 суток |
| Видео | 1 сутки |

Константы: `server/config.py`.

---

## 11. Версия

| | |
|--|--|
| Protocol | **1.1** |
| Config | `PROTOCOL_VERSION = "1.1"` |

Обратная совместимость с 1.0 частичная: клиенты без `account_id` получают `account_id ≈ device_uuid` при миграции.
