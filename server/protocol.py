"""
Veniamin JSON Protocol v1.1
All packets are JSON objects with mandatory "type" field.
"""

from enum import Enum
from typing import Any, Dict
import json
import time
import uuid


class PacketType(str, Enum):
    # Client → Server
    HELLO = "hello"
    AUTH = "auth"
    MESSAGE = "message"
    FILE = "file"
    GET_MEDIA = "get_media"
    CALL_OFFER = "call_offer"
    CALL_ANSWER = "call_answer"
    CALL_ICE = "call_ice"
    CALL_HANGUP = "call_hangup"
    CALL_REJECT = "call_reject"
    CALL_INVITE = "call_invite"
    PING = "ping"
    GET_HISTORY = "get_history"
    GET_USERS = "get_users"
    GET_GROUPS = "get_groups"
    CREATE_GROUP = "create_group"
    ADD_TO_GROUP = "add_to_group"
    REMOVE_FROM_GROUP = "remove_from_group"
    LEAVE_GROUP = "leave_group"
    ADMIN_LIST_PENDING = "admin_list_pending"
    ADMIN_ACCEPT = "admin_accept"
    ADMIN_REJECT = "admin_reject"
    ADMIN_KICK = "admin_kick"
    ADMIN_BROADCAST = "admin_broadcast"
    ADMIN_RESET_MESSAGES = "admin_reset_messages"
    TYPING = "typing"
    READ = "read"
    DELETE_MESSAGE = "delete_message"
    EDIT_MESSAGE = "edit_message"
    PIN_MESSAGE = "pin_message"
    UNPIN_MESSAGE = "unpin_message"
    GET_PINS = "get_pins"

    # Server → Client
    AUTH_PENDING = "auth_pending"
    AUTH_ACCEPTED = "auth_accepted"
    AUTH_REJECTED = "auth_rejected"
    AUTH_REQUIRED = "auth_required"
    USER_JOINED = "user_joined"
    USER_LEFT = "user_left"
    USER_LIST = "user_list"
    MESSAGE_BROADCAST = "message_broadcast"
    MESSAGE_DELETED = "message_deleted"
    MESSAGE_EDITED = "message_edited"
    PINS_UPDATED = "pins_updated"
    FILE_BROADCAST = "file_broadcast"
    MEDIA_DATA = "media_data"
    HISTORY = "history"
    PENDING_LIST = "pending_list"
    GROUP_LIST = "group_list"
    GROUP_UPDATED = "group_updated"
    ERROR = "error"
    PONG = "pong"
    SYSTEM = "system"
    SYSTEM_BROADCAST = "system_broadcast"
    CALL_INCOMING = "call_incoming"
    CALL_ANSWERED = "call_answered"
    CALL_ICE_CANDIDATE = "call_ice_candidate"
    CALL_ENDED = "call_ended"
    CALL_BUSY = "call_busy"
    CALL_PEER_JOINED = "call_peer_joined"
    CALL_PEER_LEFT = "call_peer_left"
    CALL_PARTICIPANTS = "call_participants"
    TYPING_BROADCAST = "typing_broadcast"
    READ_RECEIPT = "read_receipt"
    RESET_DONE = "reset_done"


def make_packet(ptype: PacketType | str, **kwargs) -> Dict[str, Any]:
    packet = {
        "type": ptype.value if isinstance(ptype, PacketType) else ptype,
        "ts": int(time.time() * 1000),
        "id": str(uuid.uuid4()),
    }
    packet.update(kwargs)
    return packet


def dumps(packet: Dict[str, Any]) -> str:
    return json.dumps(packet, ensure_ascii=False, separators=(",", ":"))


def loads(data: str) -> Dict[str, Any]:
    return json.loads(data)
