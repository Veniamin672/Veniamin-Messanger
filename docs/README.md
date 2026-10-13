# Документация Veniamin

Закрытый мессенджер для небольшой группы (~10 человек):  
**Python WebSocket-сервер** + **Flutter-клиент** (Windows / Android / iOS).

| Документ | Содержание |
|----------|------------|
| [SETUP.md](./SETUP.md) | Установка сервера и клиента, сброс данных, сборка |
| [protocol.md](./protocol.md) | JSON-протокол WebSocket **v1.1** |
| [ANDROID.md](./ANDROID.md) | Android: SDK 36, desugaring, picker, permissions |
| [ANDROID_FIX.md](./ANDROID_FIX.md) | Краткий чеклист compileSdk |
| [ANDROID_FILE_PICKER_FIX.md](./ANDROID_FILE_PICKER_FIX.md) | file_picker / AAR metadata |
| [ANDROID_PERMISSIONS.md](./ANDROID_PERMISSIONS.md) | Список permissions |

Корневой обзор репозитория: [`../README.md`](../README.md).

## Архитектура (одна страница)

```text
┌─────────────────────┐         WebSocket JSON          ┌──────────────────────┐
│  Flutter client     │◄───────────────────────────────►│  Python server       │
│  Windows/Android/iOS│         :8765                   │  asyncio + websockets│
│  WebRTC (media P2P) │◄────── RTP/media (STUN) ───────►│  signaling only      │
└─────────────────────┘                                 │  storage: data/      │
                                                        └──────────────────────┘
```

- **Аккаунт** (`account_id`) — кто вы в группах и правах.  
- **Устройство** (`device_uuid`) — сокет, онлайн, доставка звонка.  
- Несколько устройств на один аккаунт поддерживаются.

## Лицензия / публикация

Перед выкладкой на GitHub:

1. Не коммитить `server/data/` с живыми пользователями.  
2. Сменить пароль сброса сообщений в `config.py`.  
3. Описать в корневом README, что это **не** защищённый мессенджер для интернета без VPN/TLS.
