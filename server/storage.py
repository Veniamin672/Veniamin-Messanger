"""
Persistent storage for users, pending, groups, messages and media.
"""

import json
import os
import time
import uuid
import aiofiles
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import config


class Storage:
    def __init__(self):
        self.users: Dict[str, dict] = {}
        self.pending: Dict[str, dict] = {}
        self.groups: Dict[str, dict] = {}
        # group_id -> [ {message_id, pinned_at, pinned_by} ]
        self.pins: Dict[str, list] = {}
        self.messages: List[dict] = []
        self.admin_uuid: Optional[str] = None
        self._ensure_dirs()

    def _ensure_dirs(self):
        Path(config.DATA_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.MESSAGES_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.MEDIA_DIR).mkdir(parents=True, exist_ok=True)

    async def load(self):
        if os.path.exists(config.USERS_FILE):
            async with aiofiles.open(config.USERS_FILE, "r", encoding="utf-8") as f:
                self.users = json.loads(await f.read())
            # migrate: ensure account_id on every user
            migrated = False
            for uid, u in self.users.items():
                if not u.get("account_id"):
                    u["account_id"] = uid
                    migrated = True
            if migrated:
                await self.save_users()
        if os.path.exists(config.PENDING_FILE):
            async with aiofiles.open(config.PENDING_FILE, "r", encoding="utf-8") as f:
                self.pending = json.loads(await f.read())
        if os.path.exists(config.GROUPS_FILE):
            async with aiofiles.open(config.GROUPS_FILE, "r", encoding="utf-8") as f:
                self.groups = json.loads(await f.read())
        if os.path.exists(config.PINS_FILE):
            async with aiofiles.open(config.PINS_FILE, "r", encoding="utf-8") as f:
                raw = json.loads(await f.read())
                self.pins = {str(k): list(v) for k, v in (raw or {}).items()}
        if os.path.exists(config.ADMIN_UUID_FILE):
            async with aiofiles.open(config.ADMIN_UUID_FILE, "r", encoding="utf-8") as f:
                self.admin_uuid = (await f.read()).strip() or None

        if config.GLOBAL_GROUP_ID not in self.groups:
            accs = []
            for uid, u in self.users.items():
                aid = u.get("account_id") or uid
                if aid not in accs:
                    accs.append(aid)
            self.groups[config.GLOBAL_GROUP_ID] = {
                "id": config.GLOBAL_GROUP_ID,
                "name": "Общий",
                "owner_uuid": None,
                "members": accs,
                "created_at": int(time.time() * 1000),
            }
            await self.save_groups()
        # Normalize all groups: members = unique account_ids only
        await self._normalize_group_members()

        await self._load_recent_messages()

    async def _load_recent_messages(self):
        self.messages = []
        now = datetime.now()
        for days_back in range(8):
            day = now - timedelta(days=days_back)
            path = Path(config.MESSAGES_DIR) / f"{day.strftime('%Y-%m-%d')}.jsonl"
            if path.exists():
                async with aiofiles.open(path, "r", encoding="utf-8") as f:
                    async for line in f:
                        line = line.strip()
                        if line:
                            try:
                                self.messages.append(json.loads(line))
                            except json.JSONDecodeError:
                                pass
        self.messages.sort(key=lambda m: m.get("ts", 0))

    async def save_users(self):
        async with aiofiles.open(config.USERS_FILE, "w", encoding="utf-8") as f:
            await f.write(json.dumps(self.users, ensure_ascii=False, indent=2))

    async def save_pending(self):
        async with aiofiles.open(config.PENDING_FILE, "w", encoding="utf-8") as f:
            await f.write(json.dumps(self.pending, ensure_ascii=False, indent=2))

    
    async def save_pins(self):
        os.makedirs(config.DATA_DIR, exist_ok=True)
        async with aiofiles.open(config.PINS_FILE, "w", encoding="utf-8") as f:
            await f.write(json.dumps(self.pins, ensure_ascii=False, indent=2))

    def pinned_ids(self, group_id: str) -> set:
        return {p.get("message_id") for p in self.pins.get(group_id, []) if p.get("message_id")}

    def is_pinned(self, message_id: str, group_id: str | None = None) -> bool:
        if group_id:
            return any(p.get("message_id") == message_id for p in self.pins.get(group_id, []))
        for lst in self.pins.values():
            if any(p.get("message_id") == message_id for p in lst):
                return True
        return False

    def pins_for_group(self, group_id: str) -> list:
        """Список закрепов с телом сообщения (если ещё есть)."""
        out = []
        for p in self.pins.get(group_id, []):
            mid = p.get("message_id")
            msg = next((m for m in self.messages if m.get("id") == mid), None)
            entry = {
                "message_id": mid,
                "pinned_at": p.get("pinned_at"),
                "pinned_by": p.get("pinned_by"),
            }
            if msg:
                entry["message"] = msg
            out.append(entry)
        return out

    async def pin_message(self, message_id: str, by_uuid: str, group_id=None):
        """Returns (ok, error_or_None, group_id)."""
        msg = next((m for m in self.messages if m.get("id") == message_id), None)
        if not msg:
            return False, "message not found", None
        gid = group_id or msg.get("group_id") or config.GLOBAL_GROUP_ID
        if msg.get("msg_type") in ("system", "date"):
            return False, "cannot pin system message", gid
        lst = self.pins.setdefault(gid, [])
        if any(p.get("message_id") == message_id for p in lst):
            return True, None, gid  # already
        limit = config.MAX_PINS_GLOBAL if gid == config.GLOBAL_GROUP_ID else config.MAX_PINS_GROUP
        if len(lst) >= limit:
            return False, f"pin limit ({limit})", gid
        now = int(time.time() * 1000)
        lst.append({
            "message_id": message_id,
            "pinned_at": now,
            "pinned_by": by_uuid,
        })
        msg["pinned"] = True
        msg["pinned_at"] = now
        await self.save_pins()
        await self._rewrite_message_files()
        return True, None, gid

    async def unpin_message(self, message_id: str, group_id=None):
        gid = group_id
        if not gid:
            for g, lst in self.pins.items():
                if any(p.get("message_id") == message_id for p in lst):
                    gid = g
                    break
        if not gid:
            return False, "not pinned", None
        lst = self.pins.get(gid, [])
        new_lst = [p for p in lst if p.get("message_id") != message_id]
        if len(new_lst) == len(lst):
            return False, "not pinned", gid
        self.pins[gid] = new_lst
        msg = next((m for m in self.messages if m.get("id") == message_id), None)
        if msg:
            msg.pop("pinned", None)
            msg.pop("pinned_at", None)
            await self._rewrite_message_files()
        await self.save_pins()
        return True, None, gid

    async def save_groups(self):
        async with aiofiles.open(config.GROUPS_FILE, "w", encoding="utf-8") as f:
            await f.write(json.dumps(self.groups, ensure_ascii=False, indent=2))

    async def set_admin(self, uuid_: str):
        self.admin_uuid = uuid_
        async with aiofiles.open(config.ADMIN_UUID_FILE, "w", encoding="utf-8") as f:
            await f.write(uuid_)

    def is_admin(self, uuid_: str) -> bool:
        if not self.admin_uuid:
            return False
        if self.admin_uuid == uuid_:
            return True
        # admin could be stored as device uuid; compare accounts
        return self.account_id_of(self.admin_uuid) == self.account_id_of(uuid_)

    def is_approved(self, uuid_: str) -> bool:
        return uuid_ in self.users

    async def add_pending(self, uuid_: str, display_name: str, device_info: dict):
        self.pending[uuid_] = {
            "uuid": uuid_,
            "display_name": display_name,
            "device_info": device_info,
            "requested_at": int(time.time() * 1000),
        }
        await self.save_pending()

    async def accept_user(self, uuid_: str) -> Optional[dict]:
        if uuid_ not in self.pending:
            return None
        info = self.pending.pop(uuid_)
        account_id = info.get("account_id") or (info.get("device_info") or {}).get("account_id") or str(uuid.uuid4())
        # if linking to existing account, reuse its name/role
        existing_acc = None
        for u in self.users.values():
            if u.get("account_id") == account_id:
                existing_acc = u
                break
        user = {
            "uuid": uuid_,
            "account_id": account_id,
            "display_name": (existing_acc or info).get("display_name", info["display_name"]) if isinstance(existing_acc, dict) else info["display_name"],
            "device_info": info.get("device_info", {}),
            "joined_at": int(time.time() * 1000),
            "role": existing_acc["role"] if existing_acc else "member",
        }
        if existing_acc:
            user["display_name"] = existing_acc.get("display_name", info["display_name"])
            user["role"] = existing_acc.get("role", "member")
        self.users[uuid_] = user
        g = self.groups.get(config.GLOBAL_GROUP_ID)
        if g:
            aid = user.get("account_id") or uuid_
            if aid not in g.get("members", []):
                g.setdefault("members", []).append(aid)
                await self.save_groups()
        await self.save_users()
        await self.save_pending()
        return user

    async def reject_user(self, uuid_: str) -> bool:
        if uuid_ not in self.pending:
            return False
        del self.pending[uuid_]
        await self.save_pending()
        return True

    async def kick_user(self, uuid_: str) -> bool:
        """Kick by device uuid or account_id (removes all devices of account)."""
        # collect targets
        targets = []
        if uuid_ in self.users:
            if self.is_admin(uuid_):
                return False
            targets = [uuid_]
        else:
            for uid, u in list(self.users.items()):
                if u.get("account_id") == uuid_:
                    if self.is_admin(uid) or u.get("role") == "admin":
                        return False
                    targets.append(uid)
        if not targets:
            return False
        aids = set()
        for uid in targets:
            u = self.users.pop(uid, None)
            if u and u.get("account_id"):
                aids.add(u["account_id"])
        remove_ids = set(targets) | aids | {uuid_}
        for g in self.groups.values():
            g["members"] = [m for m in g.get("members", []) if m not in remove_ids]
        await self.save_groups()
        await self.save_users()
        return True


    def account_id_of(self, device_or_account: str) -> str:
        """device uuid → account_id; account_id → account_id."""
        if not device_or_account:
            return ""
        if device_or_account in self.users:
            return self.users[device_or_account].get("account_id") or device_or_account
        for uid, u in self.users.items():
            if u.get("account_id") == device_or_account:
                return device_or_account
        return device_or_account

    def _all_account_ids(self) -> list:
        accs = []
        for uid, u in self.users.items():
            aid = (u.get("account_id") or uid or "").strip() or uid
            if aid and aid not in accs:
                accs.append(aid)
        return accs

    def _sanitize_members(self, members: list) -> list:
        """Только account_id. Device uuid → account_id этого устройства один раз."""
        device_keys = set(self.users.keys())
        out = []
        for m in members or []:
            if not m:
                continue
            if m in device_keys:
                aid = self.users[m].get("account_id") or m
            else:
                # уже account_id (не трогаем через device)
                aid = m
            if aid and aid not in out:
                out.append(aid)
        return out

    async def _normalize_group_members(self):
        """Привести members к account_id. «Общий» = все аккаунты. Остальные — как есть."""
        changed = False
        for uid, u in self.users.items():
            if not u.get("account_id"):
                u["account_id"] = uid
                changed = True
        all_acc = self._all_account_ids()
        for g in self.groups.values():
            raw = list(g.get("members", []))
            acc = self._sanitize_members(raw)
            if g.get("id") == config.GLOBAL_GROUP_ID:
                for aid in all_acc:
                    if aid not in acc:
                        acc.append(aid)
            if g.get("owner_uuid"):
                oa = self.account_id_of(g["owner_uuid"])
                if oa and oa not in acc:
                    acc.append(oa)
                if g.get("owner_uuid") != oa:
                    g["owner_uuid"] = oa
                    changed = True
            if acc != raw:
                g["members"] = acc
                changed = True
            else:
                g["members"] = acc
        if changed:
            await self.save_groups()
            await self.save_users()

    async def create_group(self, name: str, owner_uuid: str) -> dict:
        owner_acc = self.account_id_of(owner_uuid)
        if not owner_acc:
            owner_acc = owner_uuid
        gid = str(uuid.uuid4())
        group = {
            "id": gid,
            "name": name[:64],
            "owner_uuid": owner_acc,
            "members": [owner_acc],
            "created_at": int(time.time() * 1000),
        }
        self.groups[gid] = group
        await self.save_groups()
        return group

    def _is_admin_account(self, account_or_device: str) -> bool:
        aid = self.account_id_of(account_or_device)
        if self.admin_uuid and self.account_id_of(self.admin_uuid) == aid:
            return True
        for u in self.users.values():
            if (u.get("account_id") or u.get("uuid")) == aid and u.get("role") == "admin":
                return True
        return False

    def _user_in_group(self, account_or_device: str, group: dict) -> bool:
        aid = self.account_id_of(account_or_device)
        if not aid:
            return False
        members = self._sanitize_members(group.get("members", []))
        return aid in members

    async def ensure_account_in_global(self, account_or_device: str) -> str:
        aid = self.account_id_of(account_or_device)
        if not aid:
            return ""
        if account_or_device in self.users and not self.users[account_or_device].get("account_id"):
            self.users[account_or_device]["account_id"] = aid
            await self.save_users()
        g = self.groups.get(config.GLOBAL_GROUP_ID)
        if g is None:
            self.groups[config.GLOBAL_GROUP_ID] = {
                "id": config.GLOBAL_GROUP_ID,
                "name": "Общий",
                "owner_uuid": None,
                "members": [aid],
                "created_at": int(time.time() * 1000),
            }
            await self.save_groups()
            return aid
        members = self._sanitize_members(g.get("members", []))
        if aid not in members:
            members.append(aid)
            g["members"] = members
            await self.save_groups()
        else:
            g["members"] = members
        return aid

    async def add_to_group(self, group_id: str, member_uuid: str, by_uuid: str) -> Optional[str]:
        g = self.groups.get(group_id)
        if not g:
            return "group not found"
        if group_id == config.GLOBAL_GROUP_ID:
            return "cannot modify global group members manually"
        if not member_uuid:
            return "no member specified"
        by_acc = self.account_id_of(by_uuid)
        member_acc = self.account_id_of(member_uuid)
        if not member_acc:
            return "user not found"
        g["members"] = self._sanitize_members(g.get("members", []))
        if by_acc != g.get("owner_uuid") and not self._is_admin_account(by_uuid):
            if by_acc not in g["members"]:
                return "not a member"
        known = (
            member_uuid in self.users
            or any((u.get("account_id") or uid) == member_acc for uid, u in self.users.items())
        )
        if not known:
            return "user not found"
        if member_acc not in g["members"]:
            g["members"].append(member_acc)
            await self.save_groups()
        return None

    async def remove_from_group(self, group_id: str, member_uuid: str, by_uuid: str) -> Optional[str]:
        g = self.groups.get(group_id)
        if not g:
            return "group not found"
        if group_id == config.GLOBAL_GROUP_ID:
            return "cannot modify global group"
        member_acc = self.account_id_of(member_uuid)
        by_acc = self.account_id_of(by_uuid)
        g["members"] = self._sanitize_members(g.get("members", []))
        is_owner = by_acc == g.get("owner_uuid")
        is_self = by_acc == member_acc
        if self._is_admin_account(member_uuid) and not is_self:
            return "cannot remove server admin from groups"
        if not (is_owner or self._is_admin_account(by_uuid) or is_self):
            return "no permission"
        g["members"] = [m for m in g.get("members", []) if m != member_acc]
        await self.save_groups()
        return None

    def groups_for_user(self, uuid_: str) -> List[dict]:
        """Строго: только группы, где members содержит account_id пользователя."""
        aid = self.account_id_of(uuid_)
        result = []
        if not aid:
            return result
        for g in self.groups.values():
            members = self._sanitize_members(g.get("members", []))
            if aid not in members:
                continue
            result.append({
                "id": g.get("id"),
                "name": g.get("name"),
                "owner_uuid": self.account_id_of(g["owner_uuid"]) if g.get("owner_uuid") else None,
                "members": members,
                "member_count": len(members),
                "created_at": g.get("created_at", 0),
            })
        return result

    async def delete_message(self, message_id: str, by_uuid: str) -> Optional[dict]:
        """Удаляет сообщение, только если оно принадлежит by_uuid (или его account)."""
        msg = next((m for m in self.messages if m.get("id") == message_id), None)
        if not msg:
            return None
        sender = msg.get("from_uuid") or ""
        by_acc = self.account_id_of(by_uuid)
        sender_acc = self.account_id_of(sender) if sender else ""
        is_owner = sender == by_uuid or (sender_acc and sender_acc == by_acc)
        is_admin = self._is_admin_account(by_uuid) or self.is_admin(by_uuid)
        # обычный пользователь — только свои; админ — любые (включая system/date)
        if not is_owner and not is_admin:
            return None
        if msg.get("msg_type") in ("system", "date") and not is_admin:
            return None
        self.messages = [m for m in self.messages if m.get("id") != message_id]
        # медиа
        mid = msg.get("media_id")
        if mid:
            path = self.find_media_file(mid)
            if path is not None:
                try:
                    path.unlink()
                except OSError:
                    pass
        await self._rewrite_message_files()
        return msg

    async def edit_message(self, message_id: str, by_uuid: str, new_text: str) -> Optional[dict]:
        """Только автор (по account_id). Админ НЕ может править чужие."""
        new_text = (new_text or "").strip()
        if not new_text or len(new_text) > 10000:
            return None
        msg = next((m for m in self.messages if m.get("id") == message_id), None)
        if not msg:
            return None
        if msg.get("msg_type") not in (None, "text"):
            return None  # только текст
        sender = msg.get("from_uuid") or ""
        by_acc = self.account_id_of(by_uuid)
        sender_acc = self.account_id_of(sender) if sender else ""
        if sender != by_uuid and sender_acc != by_acc:
            return None  # чужое — даже админу нельзя
        msg["text"] = new_text
        msg["edited"] = True
        msg["edited_ts"] = int(time.time() * 1000)
        await self._rewrite_message_files()
        return msg


    async def _rewrite_message_files(self):
        """Перезаписывает jsonl после удаления (маленький чат — ок)."""
        by_day: dict = {}
        for m in self.messages:
            ts = m.get("ts") or 0
            try:
                day = datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
            except (OSError, ValueError, OverflowError):
                day = "unknown"
            by_day.setdefault(day, []).append(m)
        for p in Path(config.MESSAGES_DIR).glob("*.jsonl"):
            try:
                p.unlink()
            except OSError:
                pass
        for day, msgs in by_day.items():
            if day == "unknown":
                continue
            path = Path(config.MESSAGES_DIR) / f"{day}.jsonl"
            async with aiofiles.open(path, "w", encoding="utf-8") as f:
                for m in msgs:
                    await f.write(json.dumps(m, ensure_ascii=False) + "\n")

    async def save_message(self, msg: dict):
        self.messages.append(msg)
        day = datetime.fromtimestamp(msg["ts"] / 1000).strftime("%Y-%m-%d")
        path = Path(config.MESSAGES_DIR) / f"{day}.jsonl"
        async with aiofiles.open(path, "a", encoding="utf-8") as f:
            await f.write(json.dumps(msg, ensure_ascii=False) + "\n")

    async def get_history(
        self,
        group_id: str = config.GLOBAL_GROUP_ID,
        limit: int = 200,
        before_ts: Optional[int] = None,
    ) -> List[dict]:
        result = [
            m for m in self.messages
            if m.get("group_id", config.GLOBAL_GROUP_ID) == group_id
        ]
        if before_ts:
            result = [m for m in result if m.get("ts", 0) < before_ts]
        return result[-limit:]

    async def reset_all_messages(self):
        self.messages = []
        for p in Path(config.MESSAGES_DIR).glob("*.jsonl"):
            try:
                p.unlink()
            except OSError:
                pass
        for p in Path(config.MEDIA_DIR).iterdir():
            try:
                if p.is_file():
                    p.unlink()
            except OSError:
                pass

    def media_path(self, media_id: str, ext: str = "") -> Path:
        return Path(config.MEDIA_DIR) / f"{media_id}{ext}"

    def find_media_file(self, media_id: str) -> Optional[Path]:
        for p in Path(config.MEDIA_DIR).glob(f"{media_id}*"):
            if p.is_file():
                return p
        return None

    async def cleanup(self):
        now = time.time() * 1000
        msg_cutoff = now - config.MESSAGE_RETENTION_HOURS * 3600 * 1000
        file_cutoff = now - config.FILE_PHOTO_RETENTION_HOURS * 3600 * 1000
        video_cutoff = now - config.VIDEO_RETENTION_HOURS * 3600 * 1000
        pin_cutoff = now - config.PINNED_RETENTION_HOURS * 3600 * 1000

        # снять просроченные закрепы (> 30 дней с момента pin)
        pins_changed = False
        for gid, lst in list(self.pins.items()):
            fresh = []
            for p in lst:
                pat = p.get("pinned_at") or 0
                if pat >= pin_cutoff:
                    fresh.append(p)
                else:
                    pins_changed = True
                    mid = p.get("message_id")
                    msg = next((m for m in self.messages if m.get("id") == mid), None)
                    if msg:
                        msg.pop("pinned", None)
                        msg.pop("pinned_at", None)
            self.pins[gid] = fresh
        if pins_changed:
            await self.save_pins()

        pinned_alive = set()
        for lst in self.pins.values():
            for p in lst:
                if p.get("message_id"):
                    pinned_alive.add(p["message_id"])

        keep = []
        for m in self.messages:
            mid = m.get("id")
            # закреплённые живут, пока пин актуален (до 30 дней)
            if mid in pinned_alive:
                keep.append(m)
                continue
            mtype = m.get("msg_type", "text")
            ts = m.get("ts", 0)
            if mtype in ("text", "system", "date") and ts < msg_cutoff:
                continue
            if mtype in ("file", "photo") and ts < file_cutoff:
                media = m.get("media_id")
                if media:
                    for pp in Path(config.MEDIA_DIR).glob(f"{media}*"):
                        try:
                            pp.unlink()
                        except OSError:
                            pass
                continue
            if mtype == "video" and ts < video_cutoff:
                media = m.get("media_id")
                if media:
                    for pp in Path(config.MEDIA_DIR).glob(f"{media}*"):
                        try:
                            pp.unlink()
                        except OSError:
                            pass
                continue
            keep.append(m)
        self.messages = keep

        # jsonl: не трогаем дни, где ещё есть закреплённые
        pinned_days = set()
        for m in self.messages:
            if m.get("id") in pinned_alive:
                ts = m.get("ts") or 0
                try:
                    pinned_days.add(
                        datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
                    )
                except (OSError, ValueError, OverflowError):
                    pass

        cutoff_date = datetime.now() - timedelta(days=8)
        for pp in Path(config.MESSAGES_DIR).glob("*.jsonl"):
            try:
                if pp.stem in pinned_days:
                    continue
                file_date = datetime.strptime(pp.stem, "%Y-%m-%d")
                if file_date < cutoff_date:
                    pp.unlink()
            except ValueError:
                pass
        print(f"[cleanup] done, kept {len(self.messages)} messages, pins={sum(len(v) for v in self.pins.values())}")
