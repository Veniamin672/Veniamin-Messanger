#!/usr/bin/env python3
"""Полный сброс данных сервера Veniamin: пользователи, группы, сообщения, медиа."""
import shutil
from pathlib import Path
import config

def main():
    data = Path(config.DATA_DIR)
    if data.exists():
        shutil.rmtree(data)
        print(f"Удалено: {data.resolve()}")
    else:
        print(f"Папки {data} не было")
    data.mkdir(parents=True, exist_ok=True)
    Path(config.MESSAGES_DIR).mkdir(parents=True, exist_ok=True)
    Path(config.MEDIA_DIR).mkdir(parents=True, exist_ok=True)
    print("Готово. Запусти сервер заново — первый вошедший станет админом.")
    print("На клиентах: disconnect, лучше очистить данные приложения или ввести новый аккаунт.")

if __name__ == "__main__":
    main()
