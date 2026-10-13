# Veniamin Protocol v1.0

Транспорт: **WebSocket** (text frames, UTF-8 JSON).

Каждый пакет:

```json
{
  "type": "<string>",
  "ts": 1710000000000,
  "id": "<uuid>",
  ...
}
```

`ts` — Unix timestamp в миллисекундах.  
`id` — уникальный ID пакета (генерирует отправитель).

---

## 1. Handshake

### Client → Server: `hello`

```json
{
  "type": "hello",
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "display_name": "Alice",
  "device_info": { "platform": "windows" },
  "protocol": "1.0"
}
```

### Server → Client (варианты)

**Уже одобрен:**
```json
{
  "type": "auth_accepted",
  "user": { "uuid": "...", "display_name": "Alice", "role": "admin", "joined_at": ... },
  "is_admin": true,
  "users": [ ... ]
}
```

**В ожидании:**
```json
{ "type": "auth_pending" }
```

**Новый устройство:**
```json
{ "type": "auth_required" }
```
Клиент должен сразу отправить `auth`.

---

## 2. Авторизация

### Client → Server: `auth`

```json
{
  "type": "auth",
  "display_name": "Bob",
  "device_info": { "platform": "android" }
}
```

- Если это **первый пользователь** на сервере → автоматически становится админом и получает `auth_accepted`.
- Иначе → попадает в `pending`, получает `auth_pending`.

### Admin → Server: `admin_accept` / `admin_reject`

```json
{ "type": "admin_accept", "uuid": "<device_uuid>" }
{ "type": "admin_reject", "uuid": "<device_uuid>" }
```

После `admin_accept` целевой клиент (если онлайн) получает `auth_accepted`.

---

## 3. Сообщения

### Client → Server: `message`

```json
{
  "type": "message",
  "text": "hello world"
}
```

### Server → all: `message_broadcast`

```json
{
  "type": "message_broadcast",
  "id": "...",
  "from_uuid": "...",
  "from_name": "Alice",
  "msg_type": "text",
  "text": "hello world",
  "ts": 1710000000000
}
```

### Client → Server: `file`

```json
{
  "type": "file",
  "filename": "photo.jpg",
  "mime": "image/jpeg",
  "size": 12345,
  "media_id": "optional-uuid",
  "data": "<base64>"
}
```

Сервер определяет `msg_type`: `photo` | `video` | `file` по MIME.

### Server → all: `file_broadcast`

(без поля `data`)

```json
{
  "type": "file_broadcast",
  "id": "...",
  "from_uuid": "...",
  "from_name": "Alice",
  "msg_type": "photo",
  "media_id": "...",
  "filename": "photo.jpg",
  "mime": "image/jpeg",
  "size": 12345,
  "ts": ...
}
```

---

## 4. История и пользователи

```json
{ "type": "get_history", "limit": 100, "before_ts": null }
→ { "type": "history", "messages": [ ... ] }

{ "type": "get_users" }
→ { "type": "user_list", "users": [ { "uuid", "display_name", "role", "online" } ] }

{ "type": "admin_list_pending" }   // только admin
→ { "type": "pending_list", "pending": [ ... ] }
```

---

## 5. Голосовые звонки (WebRTC signaling)

Все пакеты содержат `to_uuid` и `call_id`.

| Client → Server | Server → target |
|-----------------|-----------------|
| `call_offer` + `sdp` | `call_incoming` |
| `call_answer` + `sdp` | `call_answered` |
| `call_ice` + `candidate` | `call_ice_candidate` |
| `call_hangup` | `call_ended` |
| `call_reject` | `call_ended` |

Пример offer:

```json
{
  "type": "call_offer",
  "to_uuid": "...",
  "call_id": "...",
  "sdp": { "type": "offer", "sdp": "v=0\r\n..." }
}
```

ICE candidate:

```json
{
  "type": "call_ice",
  "to_uuid": "...",
  "call_id": "...",
  "candidate": {
    "candidate": "candidate:1 1 UDP ...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

---

## 6. Служебные

```json
{ "type": "ping" }  →  { "type": "pong" }
{ "type": "typing", "is_typing": true }
→ { "type": "typing_broadcast", "uuid": "...", "display_name": "...", "is_typing": true }

{ "type": "error", "message": "..." }
{ "type": "system", "message": "You were kicked by admin" }
```

---

## 7. Авто-удаление (сервер)

Каждый день в **03:00** (локальное время сервера):

| Тип | Срок хранения |
|-----|---------------|
| text | 7 суток |
| file / photo | 3 суток |
| video | 1 сутки |

Сообщения старше удаляются из памяти и с диска; медиа-файлы — из `data/media/`.
