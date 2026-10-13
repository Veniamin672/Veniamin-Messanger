#!/usr/bin/env python3
"""
Veniamin — closed group messenger server v1.1
"""

import asyncio
import json
import time
from datetime import datetime
import uuid
import base64
import traceback
from pathlib import Path
from typing import Dict, Optional

import websockets
from websockets.asyncio.server import serve, ServerConnection

import config
from protocol import PacketType, make_packet, dumps, loads
from storage import Storage



def _now() -> str:
    """Local time for console logs."""
    return datetime.now().strftime("%H:%M:%S")

class Client:
    def __init__(self, ws: ServerConnection, device_uuid: str):
        self.ws = ws
        self.uuid = device_uuid
        self.display_name: str = ""
        self.authenticated = False
        self.is_admin = False
        self.account_id: str = ""
        self.platform: str = "unknown"


class VeniaminServer:
    def __init__(self):
        self.storage = Storage()
        self.clients: Dict[str, Client] = {}
        self.connections: Dict[ServerConnection, Client] = {}
        # account_id -> {"peer": account_id, "call_id": str}
        self.active_calls: Dict[str, dict] = {}
        self._cleanup_task: Optional[asyncio.Task] = None
        self._date_sep_task: Optional[asyncio.Task] = None

    async def start(self):
        await self.storage.load()
        print(f"[Veniamin] users={len(self.storage.users)} pending={len(self.storage.pending)} "
              f"groups={len(self.storage.groups)}")
        if self.storage.admin_uuid:
            print(f"[Veniamin] admin={self.storage.admin_uuid[:8]}…")
        else:
            print("[Veniamin] no admin yet — first user becomes admin")

        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        self._date_sep_task = asyncio.create_task(self._date_separator_loop())

        async with serve(
            self.handler,
            config.HOST,
            config.PORT,
            max_size=config.MAX_FILE_SIZE + 512 * 1024,
            ping_interval=20,
            ping_timeout=30,
        ):
            print(f"[Veniamin] ws://{config.HOST}:{config.PORT}")
            await asyncio.Future()

    async def _cleanup_loop(self):
        while True:
            now = time.localtime()
            target = time.mktime((
                now.tm_year, now.tm_mon, now.tm_mday,
                config.CLEANUP_HOUR, config.CLEANUP_MINUTE, 0,
                now.tm_wday, now.tm_yday, now.tm_isdst,
            ))
            if target <= time.time():
                target += 86400
            await asyncio.sleep(target - time.time())
            try:
                await self.storage.cleanup()
            except Exception as e:
                print(f"[cleanup] {e}")

    async def _date_separator_loop(self):
        """Каждый день в 00:00 — системное сообщение с датой во все группы."""
        while True:
            now = time.localtime()
            target = time.mktime((
                now.tm_year, now.tm_mon, now.tm_mday,
                config.DATE_SEPARATOR_HOUR, config.DATE_SEPARATOR_MINUTE, 0,
                now.tm_wday, now.tm_yday, now.tm_isdst,
            ))
            if target <= time.time():
                target += 86400
            await asyncio.sleep(target - time.time())
            try:
                await self._send_date_separators()
            except Exception as e:
                print(f"[date_sep] {e}")

    async def _send_date_separators(self):
        # local date at midnight
        d = time.localtime()
        label = time.strftime("%d/%m/%Y", d)
        text = f"--- {label} ---"
        ts = int(time.time() * 1000)
        for gid in list(self.storage.groups.keys()):
            msg = {
                "id": str(uuid.uuid4()),
                "from_uuid": "system",
                "from_name": "SYSTEM",
                "group_id": gid,
                "msg_type": "date",
                "text": text,
                "ts": ts,
            }
            await self.storage.save_message(msg)
            await self.broadcast(
                make_packet(PacketType.SYSTEM_BROADCAST, **msg),
                group_id=gid,
            )
        print(f"[date_sep] {text} → {len(self.storage.groups)} groups")

    async def handler(self, ws: ServerConnection):
        client: Optional[Client] = None
        try:
            async for raw in ws:
                try:
                    packet = loads(raw)
                except json.JSONDecodeError:
                    await self.send(ws, make_packet(PacketType.ERROR, message="Invalid JSON"))
                    continue
                ptype = packet.get("type")
                if not ptype:
                    await self.send(ws, make_packet(PacketType.ERROR, message="Missing type"))
                    continue
                if client is None:
                    if ptype != PacketType.HELLO:
                        await self.send(ws, make_packet(PacketType.ERROR, message="Expected hello"))
                        await ws.close()
                        return
                    client = await self.handle_hello(ws, packet)
                    if client is None:
                        return
                    continue
                await self.dispatch(client, packet)
        except websockets.ConnectionClosed:
            pass
        except Exception as e:
            print(f"[error] {e}\n{traceback.format_exc()}")
        finally:
            if client:
                await self.disconnect(client)

    async def send(self, ws: ServerConnection, packet: dict):
        try:
            await ws.send(dumps(packet))
        except Exception:
            pass

    async def send_to(self, uuid_: str, packet: dict):
        c = self.clients.get(uuid_)
        if c:
            await self.send(c.ws, packet)

    async def broadcast(self, packet: dict, exclude: Optional[str] = None,
                        group_id: Optional[str] = None):
        data = dumps(packet)
        members = None
        if group_id:
            g = self.storage.groups.get(group_id)
            if g:
                members = set(g.get("members", []))
        for uid, c in list(self.clients.items()):
            if uid == exclude or not c.authenticated:
                continue
            if group_id is not None and not self._in_group(uid, group_id):
                continue
            try:
                await c.ws.send(data)
            except Exception:
                pass

    async def broadcast_admins(self, packet: dict):
        data = dumps(packet)
        for uid, c in list(self.clients.items()):
            if c.authenticated and c.is_admin:
                try:
                    await c.ws.send(data)
                except Exception:
                    pass

    async def handle_hello(self, ws: ServerConnection, packet: dict) -> Optional[Client]:
        device_uuid = packet.get("device_uuid")
        if not device_uuid or not isinstance(device_uuid, str) or len(device_uuid) < 10:
            await self.send(ws, make_packet(PacketType.ERROR, message="Invalid device_uuid"))
            await ws.close()
            return None

        if device_uuid in self.clients:
            old = self.clients[device_uuid]
            try:
                await old.ws.close()
            except Exception:
                pass
            self.connections.pop(old.ws, None)

        client = Client(ws, device_uuid)
        self.clients[device_uuid] = client
        self.connections[ws] = client

        display_name = packet.get("display_name", "Anonymous")
        client.display_name = display_name
        client.platform = (packet.get("device_info") or {}).get("platform", "unknown")
        client.account_id = packet.get("account_id") or ""

        requested_account = (packet.get("account_id") or "").strip()

        if self.storage.is_approved(device_uuid):
            user = self.storage.users[device_uuid]
            # Re-link device to another existing account if user provided account_id
            if requested_account and user.get("account_id") != requested_account:
                target = None
                for u in self.storage.users.values():
                    if u.get("account_id") == requested_account:
                        target = u
                        break
                old_acc = user.get("account_id")
                user["account_id"] = requested_account
                if target is not None:
                    user["display_name"] = target.get("display_name", user.get("display_name"))
                    user["role"] = target.get("role", user.get("role", "member"))
                    print(f"[{_now()}] [relink] device {device_uuid[:8]}… {str(old_acc)[:8]}… → {requested_account[:8]}…")
                else:
                    # новый / другой account_id на том же устройстве
                    user["role"] = "member"
                    print(f"[{_now()}] [relink] device {device_uuid[:8]}… → new account {requested_account[:8]}…")
                # устройство больше не должно «тащить» старые группы: members только по account
                await self.storage.ensure_account_in_global(requested_account)
            client.authenticated = True
            client.is_admin = (
                self.storage.is_admin(device_uuid)
                or user.get("role") == "admin"
                or any(
                    self.storage.is_admin(u["uuid"]) or u.get("role") == "admin"
                    for u in self.storage.users.values()
                    if u.get("account_id") == user.get("account_id")
                )
            )
            client.display_name = user.get("display_name", display_name)
            client.account_id = user.get("account_id") or device_uuid
            user["account_id"] = client.account_id
            user["device_info"] = packet.get("device_info") or user.get("device_info") or {}
            await self.storage.save_users()
            await self.storage.ensure_account_in_global(client.account_id)
            groups = self.storage.groups_for_user(device_uuid)
            await self.send(ws, make_packet(
                PacketType.AUTH_ACCEPTED,
                user={**user, "account_id": client.account_id},
                is_admin=client.is_admin,
                users=self._account_user_list(),
                groups=groups,
            ))
            await self.broadcast(make_packet(
                PacketType.USER_JOINED,
                uuid=client.account_id,
                display_name=client.display_name,
            ), exclude=device_uuid)
            print(f"[{_now()}] [+] {client.display_name} вошёл  account={client.account_id[:8]}… ({device_uuid[:8]}…)")
        elif device_uuid in self.storage.pending:
            await self.send(ws, make_packet(PacketType.AUTH_PENDING))
        else:
            await self.send(ws, make_packet(PacketType.AUTH_REQUIRED))
        return client

    async def dispatch(self, client: Client, packet: dict):
        ptype = packet.get("type")
        handlers = {
            PacketType.AUTH: self.handle_auth,
            PacketType.PING: self.handle_ping,
            PacketType.MESSAGE: self.handle_message,
            PacketType.DELETE_MESSAGE: self.handle_delete_message,
            PacketType.EDIT_MESSAGE: self.handle_edit_message,
            PacketType.FILE: self.handle_file,
            PacketType.GET_MEDIA: self.handle_get_media,
            PacketType.GET_HISTORY: self.handle_get_history,
            PacketType.GET_USERS: self.handle_get_users,
            PacketType.GET_GROUPS: self.handle_get_groups,
            PacketType.CREATE_GROUP: self.handle_create_group,
            PacketType.ADD_TO_GROUP: self.handle_add_to_group,
            PacketType.REMOVE_FROM_GROUP: self.handle_remove_from_group,
            PacketType.LEAVE_GROUP: self.handle_leave_group,
            PacketType.ADMIN_LIST_PENDING: self.handle_admin_list_pending,
            PacketType.ADMIN_ACCEPT: self.handle_admin_accept,
            PacketType.ADMIN_REJECT: self.handle_admin_reject,
            PacketType.ADMIN_KICK: self.handle_admin_kick,
            PacketType.ADMIN_BROADCAST: self.handle_admin_broadcast,
            PacketType.ADMIN_RESET_MESSAGES: self.handle_admin_reset,
            PacketType.CALL_OFFER: self.handle_call_relay,
            PacketType.CALL_ANSWER: self.handle_call_relay,
            PacketType.CALL_ICE: self.handle_call_relay,
            PacketType.CALL_HANGUP: self.handle_call_relay,
            PacketType.CALL_REJECT: self.handle_call_relay,
            PacketType.TYPING: self.handle_typing,
            PacketType.READ: self.handle_read,
        }
        handler = handlers.get(ptype)
        if handler:
            await handler(client, packet)
        else:
            await self.send(client.ws, make_packet(
                PacketType.ERROR, message=f"Unknown type: {ptype}"
            ))

    async def handle_auth(self, client: Client, packet: dict):
        if client.authenticated:
            return
        display_name = packet.get("display_name") or client.display_name or "Anonymous"
        device_info = packet.get("device_info", {})
        client.display_name = display_name

        account_id = packet.get("account_id") or client.account_id or None
        client.platform = device_info.get("platform", client.platform)

        # Link to existing account if account_id matches an approved user
        if account_id:
            for u in self.storage.users.values():
                if u.get("account_id") == account_id:
                    # auto-approve this device under same account
                    linked = {
                        "uuid": client.uuid,
                        "account_id": account_id,
                        "display_name": u.get("display_name", display_name),
                        "device_info": device_info,
                        "joined_at": int(time.time() * 1000),
                        "role": u.get("role", "member"),
                    }
                    self.storage.users[client.uuid] = linked
                    g = self.storage.groups.get(config.GLOBAL_GROUP_ID)
                    if g and (client.account_id or client.uuid) not in g.get("members", []):
                        g.setdefault("members", []).append(client.account_id or client.uuid)
                        await self.storage.save_groups()
                    await self.storage.save_users()
                    client.authenticated = True
                    client.is_admin = self.storage.is_admin(client.uuid) or u.get("role") == "admin"
                    # admin is by device uuid of first admin - if any device of admin account
                    if u.get("role") == "admin" or self.storage.is_admin(u["uuid"]):
                        client.is_admin = True
                    client.display_name = linked["display_name"]
                    client.account_id = account_id
                    await self.storage.ensure_account_in_global(getattr(client, "account_id", None) or client.uuid)
                    groups = self.storage.groups_for_user(client.uuid)
                    await self.send(client.ws, make_packet(
                        PacketType.AUTH_ACCEPTED,
                        user=linked,
                        is_admin=client.is_admin,
                        users=self._account_user_list(),
                        groups=groups,
                    ))
                    await self.broadcast(make_packet(
                        PacketType.USER_JOINED,
                        uuid=account_id,
                        display_name=client.display_name,
                    ), exclude=client.uuid)
                    print(f"[{_now()}] [link] {display_name} устройство привязано к account={account_id[:8]}…")
                    return

        if not self.storage.users and not self.storage.pending:
            account_id = str(__import__("uuid").uuid4())
            user = {
                "uuid": client.uuid,
                "account_id": account_id,
                "display_name": display_name,
                "device_info": device_info,
                "joined_at": int(time.time() * 1000),
                "role": "admin",
            }
            self.storage.users[client.uuid] = user
            await self.storage.set_admin(client.uuid)
            g = self.storage.groups.get(config.GLOBAL_GROUP_ID)
            if g and (client.account_id or client.uuid) not in g.get("members", []):
                g.setdefault("members", []).append(client.account_id or client.uuid)
                await self.storage.save_groups()
            await self.storage.save_users()
            client.authenticated = True
            client.is_admin = True
            client.account_id = account_id
            await self.storage.ensure_account_in_global(getattr(client, "account_id", None) or client.uuid)
            groups = self.storage.groups_for_user(client.uuid)
            await self.send(client.ws, make_packet(
                PacketType.AUTH_ACCEPTED,
                user=user,
                is_admin=True,
                users=self._account_user_list(),
                groups=groups,
            ))
            print(f"[{_now()}] [ADMIN] {display_name} вошёл (первый админ) account={account_id[:8]}…")
            return

        # pending with optional account_id
        await self.storage.add_pending(client.uuid, display_name, {
            **device_info,
            "account_id": account_id,
        })
        await self.send(client.ws, make_packet(PacketType.AUTH_PENDING))
        await self.broadcast_admins(make_packet(
            PacketType.PENDING_LIST,
            pending=list(self.storage.pending.values()),
        ))

    async def handle_ping(self, client: Client, packet: dict):
        await self.send(client.ws, make_packet(PacketType.PONG))



    async def handle_edit_message(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        message_id = packet.get("message_id") or packet.get("id")
        new_text = packet.get("text") or ""
        if not message_id:
            return
        msg = await self.storage.edit_message(message_id, client.uuid, new_text)
        if not msg:
            await self.send(client.ws, make_packet(
                PacketType.ERROR, message="Cannot edit (not found or not yours)"
            ))
            return
        group_id = msg.get("group_id") or config.GLOBAL_GROUP_ID
        await self.broadcast(
            make_packet(
                PacketType.MESSAGE_EDITED,
                message_id=message_id,
                text=msg.get("text"),
                edited=True,
                edited_ts=msg.get("edited_ts"),
                group_id=group_id,
            ),
            group_id=group_id,
        )
        print(f"[{_now()}] [edit] {client.display_name} правил {str(message_id)[:8]}…")

    async def handle_delete_message(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        message_id = packet.get("message_id") or packet.get("id")
        if not message_id:
            return
        msg = await self.storage.delete_message(message_id, client.uuid)
        if not msg:
            await self.send(client.ws, make_packet(
                PacketType.ERROR, message="Cannot delete (not found or not yours)"
            ))
            return
        group_id = msg.get("group_id") or config.GLOBAL_GROUP_ID
        await self.broadcast(
            make_packet(
                PacketType.MESSAGE_DELETED,
                message_id=message_id,
                group_id=group_id,
            ),
            group_id=group_id,
        )
        print(f"[{_now()}] [del] {client.display_name} удалил сообщение {str(message_id)[:8]}…")

    async def handle_message(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        text = packet.get("text", "")
        if not text or len(text) > 10000:
            return
        group_id = packet.get("group_id") or config.GLOBAL_GROUP_ID
        g = self.storage.groups.get(group_id)
        if not g or not self._in_group(client.uuid, group_id):
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Not in group"))
            return
        msg = {
            "id": packet.get("id") or str(uuid.uuid4()),
            "from_uuid": client.uuid,
            "from_name": client.display_name,
            "group_id": group_id,
            "msg_type": "text",
            "text": text,
            "ts": int(time.time() * 1000),
        }
        # ответ на сообщение
        reply_to = packet.get("reply_to")
        if isinstance(reply_to, dict) and reply_to.get("id"):
            msg["reply_to"] = {
                "id": str(reply_to.get("id")),
                "from_name": str(reply_to.get("from_name") or "")[:64],
                "text": str(reply_to.get("text") or "")[:200],
                "msg_type": str(reply_to.get("msg_type") or "text"),
            }
        await self.storage.save_message(msg)
        await self.broadcast(
            make_packet(PacketType.MESSAGE_BROADCAST, **msg),
            group_id=group_id,
        )

    async def handle_file(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        group_id = packet.get("group_id") or config.GLOBAL_GROUP_ID
        g = self.storage.groups.get(group_id)
        if not g or not self._in_group(client.uuid, group_id):
            return
        media_id = packet.get("media_id") or str(uuid.uuid4())
        filename = packet.get("filename", "file")
        mime = packet.get("mime", "application/octet-stream")
        size = packet.get("size", 0)
        data_b64 = packet.get("data")

        if size > config.MAX_FILE_SIZE:
            await self.send(client.ws, make_packet(PacketType.ERROR, message="File too large"))
            return

        ext = Path(filename).suffix
        path = self.storage.media_path(media_id, ext)
        if data_b64:
            try:
                raw = base64.b64decode(data_b64)
                path.write_bytes(raw)
                size = len(raw)
            except Exception as e:
                await self.send(client.ws, make_packet(PacketType.ERROR, message=str(e)))
                return

        msg_type = "file"
        if mime.startswith("image/"):
            msg_type = "photo"
        elif mime.startswith("video/"):
            msg_type = "video"

        msg = {
            "id": packet.get("id") or str(uuid.uuid4()),
            "from_uuid": client.uuid,
            "from_name": client.display_name,
            "group_id": group_id,
            "msg_type": msg_type,
            "media_id": media_id,
            "filename": filename,
            "mime": mime,
            "size": size,
            "ts": int(time.time() * 1000),
        }
        await self.storage.save_message(msg)
        await self.broadcast(
            make_packet(PacketType.FILE_BROADCAST, **msg),
            group_id=group_id,
        )

    async def handle_get_media(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        media_id = packet.get("media_id")
        if not media_id:
            return
        path = self.storage.find_media_file(media_id)
        if not path or not path.exists():
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Media not found"))
            return
        try:
            raw = path.read_bytes()
            if len(raw) > config.MAX_FILE_SIZE:
                await self.send(client.ws, make_packet(PacketType.ERROR, message="File too large to send"))
                return
            b64 = base64.b64encode(raw).decode("ascii")
            await self.send(client.ws, make_packet(
                PacketType.MEDIA_DATA,
                media_id=media_id,
                filename=path.name,
                data=b64,
                size=len(raw),
            ))
        except Exception as e:
            await self.send(client.ws, make_packet(PacketType.ERROR, message=str(e)))

    async def handle_get_history(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        group_id = packet.get("group_id") or config.GLOBAL_GROUP_ID
        limit = min(int(packet.get("limit", 100)), 500)
        before = packet.get("before_ts")
        history = await self.storage.get_history(group_id, limit, before)
        await self.send(client.ws, make_packet(
            PacketType.HISTORY, messages=history, group_id=group_id
        ))

    async def handle_get_users(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        await self.send(client.ws, make_packet(
            PacketType.USER_LIST, users=self._account_user_list()
        ))

    def _account_user_list(self):
        """Aggregate devices into accounts with online platforms."""
        accounts = {}
        online_devices = {
            uid: c for uid, c in self.clients.items() if c.authenticated
        }
        for u in self.storage.users.values():
            aid = u.get("account_id") or u["uuid"]
            if aid not in accounts:
                accounts[aid] = {
                    "uuid": aid,
                    "account_id": aid,
                    "display_name": u.get("display_name", "?"),
                    "role": u.get("role", "member"),
                    "online": False,
                    "platforms": [],
                    "call_device_uuid": None,
                    "device_uuids": [],
                }
            if u.get("role") == "admin":
                accounts[aid]["role"] = "admin"
            du = u["uuid"]
            if du not in accounts[aid]["device_uuids"]:
                accounts[aid]["device_uuids"].append(du)
            if du in online_devices:
                accounts[aid]["online"] = True
                plat = online_devices[du].platform or (
                    (u.get("device_info") or {}).get("platform") or "unknown"
                )
                plat = str(plat).lower()
                if plat not in accounts[aid]["platforms"]:
                    accounts[aid]["platforms"].append(plat)
                if not accounts[aid]["call_device_uuid"]:
                    accounts[aid]["call_device_uuid"] = du
        return list(accounts.values())

    def _in_group(self, device_uuid: str, group_id: str) -> bool:
        g = self.storage.groups.get(group_id)
        if not g:
            return False
        return self.storage._user_in_group(device_uuid, g)


    async def _notify_group_members(self, group: dict, packet: dict, also=None):
        targets = set(group.get("members", []))
        if also:
            targets |= set(also)
        device_targets = set()
        for mid in targets:
            for uid in self._resolve_online_devices(mid):
                device_targets.add(uid)
        for uid in device_targets:
            await self.send_to(uid, packet)
            await self.send_to(uid, make_packet(
                PacketType.GROUP_LIST,
                groups=self.storage.groups_for_user(uid),
            ))

    async def handle_get_groups(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        await self.storage.ensure_account_in_global(getattr(client, "account_id", None) or client.uuid)
        groups = self.storage.groups_for_user(client.uuid)
        await self.send(client.ws, make_packet(PacketType.GROUP_LIST, groups=groups))

    async def handle_create_group(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        name = (packet.get("name") or "").strip()
        if not name:
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Name required"))
            return
        if len(self.storage.groups) >= config.MAX_GROUPS:
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Too many groups"))
            return
        group = await self.storage.create_group(name, client.uuid)
        await self._notify_group_members(
            group, make_packet(PacketType.GROUP_UPDATED, group=group, action="created")
        )
        groups = self.storage.groups_for_user(client.uuid)
        await self.send(client.ws, make_packet(PacketType.GROUP_LIST, groups=groups))
        print(f"[group] created «{name}» by {client.display_name}")

    async def handle_add_to_group(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        gid = packet.get("group_id")
        member = packet.get("member_uuid")
        err = await self.storage.add_to_group(gid, member, client.uuid)
        if err:
            await self.send(client.ws, make_packet(PacketType.ERROR, message=err))
            return
        group = self.storage.groups[gid]
        await self._notify_group_members(
            group, make_packet(PacketType.GROUP_UPDATED, group=group, action="member_added")
        )

    async def handle_remove_from_group(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        gid = packet.get("group_id")
        member = packet.get("member_uuid")
        err = await self.storage.remove_from_group(gid, member, client.uuid)
        if err:
            await self.send(client.ws, make_packet(PacketType.ERROR, message=err))
            return
        group = self.storage.groups[gid]
        await self._notify_group_members(
            group,
            make_packet(PacketType.GROUP_UPDATED, group=group, action="member_removed"),
            also=[member],
        )

    async def handle_leave_group(self, client: Client, packet: dict):
        packet = {**packet, "member_uuid": client.account_id or client.uuid}
        await self.handle_remove_from_group(client, packet)

    async def handle_admin_list_pending(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        await self.send(client.ws, make_packet(
            PacketType.PENDING_LIST,
            pending=list(self.storage.pending.values()),
        ))

    async def handle_admin_accept(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        target = packet.get("uuid")
        user = await self.storage.accept_user(target)
        if not user:
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Not in pending"))
            return
        target_client = self.clients.get(target)
        if target_client:
            target_client.authenticated = True
            target_client.is_admin = False
            target_client.display_name = user["display_name"]
            # ensure membership
            target_client.account_id = user.get("account_id") or target
            await self.storage.ensure_account_in_global(target_client.account_id)
            groups = self.storage.groups_for_user(target)
            await self.send(target_client.ws, make_packet(
                PacketType.AUTH_ACCEPTED,
                user=user,
                is_admin=False,
                users=self._account_user_list(),
                groups=groups,
            ))
        await self.broadcast(make_packet(
            PacketType.USER_JOINED, uuid=target, display_name=user["display_name"]
        ))
        await self.broadcast_admins(make_packet(
            PacketType.PENDING_LIST, pending=list(self.storage.pending.values())
        ))
        # refresh groups for everyone (member counts)
        for uid, c in list(self.clients.items()):
            if c.authenticated:
                await self.send(c.ws, make_packet(
                    PacketType.GROUP_LIST,
                    groups=self.storage.groups_for_user(uid),
                ))

    async def handle_admin_reject(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        target = packet.get("uuid")
        if await self.storage.reject_user(target):
            tc = self.clients.get(target)
            if tc:
                await self.send(tc.ws, make_packet(PacketType.AUTH_REJECTED))
                await tc.ws.close()
            await self.broadcast_admins(make_packet(
                PacketType.PENDING_LIST, pending=list(self.storage.pending.values())
            ))

    async def handle_admin_kick(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        target = packet.get("uuid")
        # find device uuids to disconnect before deleting
        to_close = []
        for uid, u in list(self.storage.users.items()):
            if uid == target or u.get("account_id") == target:
                to_close.append(uid)
        if await self.storage.kick_user(target):
            for uid in to_close:
                tc = self.clients.get(uid)
                if tc:
                    try:
                        await self.send(tc.ws, make_packet(
                            PacketType.SYSTEM, message="You were kicked by admin"
                        ))
                        await tc.ws.close()
                    except Exception:
                        pass
            await self.broadcast(make_packet(PacketType.USER_LEFT, uuid=target))

    async def handle_admin_broadcast(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        text = (packet.get("text") or "").strip()
        if not text:
            return
        ts = int(time.time() * 1000)
        # во все группы, не только «Общий»
        for gid in list(self.storage.groups.keys()):
            msg = {
                "id": str(uuid.uuid4()),
                "from_uuid": "system",
                "from_name": "SYSTEM",
                "group_id": gid,
                "msg_type": "system",
                "text": text,
                "ts": ts,
            }
            await self.storage.save_message(msg)
            await self.broadcast(
                make_packet(PacketType.SYSTEM_BROADCAST, **msg),
                group_id=gid,
            )
        print(f"[admin broadcast] {text[:50]} → {len(self.storage.groups)} groups")

    async def handle_admin_reset(self, client: Client, packet: dict):
        if not client.is_admin:
            return
        password = str(packet.get("password", ""))
        if password != config.ADMIN_RESET_PASSWORD:
            await self.send(client.ws, make_packet(PacketType.ERROR, message="Wrong password"))
            return
        await self.storage.reset_all_messages()
        await self.broadcast(make_packet(
            PacketType.RESET_DONE,
            message="All messages and media have been wiped by admin",
        ))
        print("[admin] full message reset")

    def _resolve_online_devices(self, target: str) -> list:
        """target = device uuid or account_id → list of online device uuids."""
        if not target:
            return []
        found = []
        # direct device
        c = self.clients.get(target)
        if c and c.authenticated:
            found.append(target)
        # all devices of this account
        for uid, u in self.storage.users.items():
            aid = u.get("account_id") or uid
            if aid == target or uid == target:
                cl = self.clients.get(uid)
                if cl and cl.authenticated and uid not in found:
                    found.append(uid)
        return found

    def _same_account(self, device_a: str, device_b: str) -> bool:
        if device_a == device_b:
            return True
        ua = self.storage.users.get(device_a) or {}
        ub = self.storage.users.get(device_b) or {}
        aa = ua.get("account_id") or device_a
        ab = ub.get("account_id") or device_b
        return aa == ab

    def _call_account(self, device_or_account: str) -> str:
        return self.storage.account_id_of(device_or_account) or device_or_account

    def _clear_call_accounts(self, *accounts: str):
        for a in accounts:
            if not a:
                continue
            info = self.active_calls.pop(a, None)
            if info and info.get("peer"):
                self.active_calls.pop(info["peer"], None)

    async def handle_call_relay(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        target = packet.get("to_uuid")
        if not target:
            return
        ptype = packet["type"]
        caller_acc = self._call_account(client.account_id or client.uuid)
        target_acc = self._call_account(target)
        call_id = packet.get("call_id")

        # исходящий звонок — проверка «линия занята»
        if ptype == PacketType.CALL_OFFER:
            if self._same_account(client.uuid, target):
                await self.send(client.ws, make_packet(
                    PacketType.ERROR, message="нельзя позвонить самому себе"
                ))
                return
            busy = False
            if target_acc in self.active_calls:
                busy = True
            if caller_acc in self.active_calls:
                busy = True
            # любой онлайн-девайс цели уже в звонке
            for tuid in self._resolve_online_devices(target):
                tacc = self._call_account(tuid)
                if tacc in self.active_calls:
                    busy = True
            if busy:
                await self.send(client.ws, make_packet(
                    PacketType.CALL_BUSY,
                    to_uuid=target,
                    call_id=call_id,
                    message="Линия этого абонента занята, попробуйте перезвонить позже",
                ))
                print(f"[{_now()}] [call] busy {client.display_name} → {target_acc[:8]}…")
                return
            targets = [
                tuid for tuid in self._resolve_online_devices(target)
                if not self._same_account(client.uuid, tuid)
            ]
            if not targets:
                await self.send(client.ws, make_packet(
                    PacketType.CALL_BUSY,
                    to_uuid=target,
                    call_id=call_id,
                    message="Абонент недоступен",
                ))
                return
            # резервируем линию (звонок / гудки)
            self.active_calls[caller_acc] = {"peer": target_acc, "call_id": call_id}
            self.active_calls[target_acc] = {"peer": caller_acc, "call_id": call_id}
            out = make_packet(
                PacketType.CALL_INCOMING,
                from_uuid=client.uuid,
                from_name=client.display_name,
                from_account=client.account_id or client.uuid,
                to_uuid=target,
                sdp=packet.get("sdp"),
                candidate=packet.get("candidate"),
                call_id=call_id,
            )
            for tuid in targets:
                await self.send_to(tuid, out)
            return

        if ptype in (PacketType.CALL_HANGUP, PacketType.CALL_REJECT):
            self._clear_call_accounts(caller_acc, target_acc)

        mapping = {
            PacketType.CALL_ANSWER: PacketType.CALL_ANSWERED,
            PacketType.CALL_ICE: PacketType.CALL_ICE_CANDIDATE,
            PacketType.CALL_HANGUP: PacketType.CALL_ENDED,
            PacketType.CALL_REJECT: PacketType.CALL_ENDED,
        }
        out_type = mapping.get(ptype, ptype)
        out = make_packet(
            out_type,
            from_uuid=client.uuid,
            from_name=client.display_name,
            from_account=client.account_id or client.uuid,
            to_uuid=target,
            sdp=packet.get("sdp"),
            candidate=packet.get("candidate"),
            call_id=call_id,
        )
        targets = self._resolve_online_devices(target)
        for tuid in targets:
            if self._same_account(client.uuid, tuid):
                continue
            await self.send_to(tuid, out)

    async def handle_typing(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        group_id = packet.get("group_id") or config.GLOBAL_GROUP_ID
        await self.broadcast(make_packet(
            PacketType.TYPING_BROADCAST,
            uuid=client.uuid,
            display_name=client.display_name,
            group_id=group_id,
            is_typing=packet.get("is_typing", True),
        ), exclude=client.uuid, group_id=group_id)

    async def handle_read(self, client: Client, packet: dict):
        if not client.authenticated:
            return
        await self.broadcast(make_packet(
            PacketType.READ_RECEIPT,
            uuid=client.uuid,
            message_id=packet.get("message_id"),
        ), exclude=client.uuid)

    async def disconnect(self, client: Client):
        self.clients.pop(client.uuid, None)
        self.connections.pop(client.ws, None)
        if client.authenticated:
            acc = self._call_account(client.account_id or client.uuid)
            if acc in self.active_calls:
                peer = (self.active_calls.get(acc) or {}).get("peer")
                self._clear_call_accounts(acc)
                # уведомить собеседника, что звонок оборвался
                if peer:
                    for tuid in self._resolve_online_devices(peer):
                        await self.send_to(tuid, make_packet(
                            PacketType.CALL_ENDED,
                            from_uuid=client.uuid,
                            from_name=client.display_name,
                            reason="disconnect",
                        ))
            await self.broadcast(make_packet(
                PacketType.USER_LEFT,
                uuid=client.uuid,
                display_name=client.display_name,
            ))
            print(f"[{_now()}] [-] {client.display_name} вышел")


async def main():
    server = VeniaminServer()
    await server.start()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[Veniamin] Shutdown")
