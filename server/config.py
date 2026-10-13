# Veniamin Server Configuration

HOST = "0.0.0.0"
PORT = 8765

# Paths
DATA_DIR = "data"
USERS_FILE = "data/users.json"
MESSAGES_DIR = "data/messages"
MEDIA_DIR = "data/media"
PENDING_FILE = "data/pending.json"
ADMIN_UUID_FILE = "data/admin_uuid.txt"
GROUPS_FILE = "data/groups.json"

# Retention (hours)
MESSAGE_RETENTION_HOURS = 7 * 24      # 7 days
FILE_PHOTO_RETENTION_HOURS = 3 * 24   # 3 days
VIDEO_RETENTION_HOURS = 24            # 1 day

# Cleanup time (server local time)
CLEANUP_HOUR = 3
CLEANUP_MINUTE = 0

# Daily date separator message (server local time)
DATE_SEPARATOR_HOUR = 0
DATE_SEPARATOR_MINUTE = 0

# Limits
MAX_MESSAGE_SIZE = 1024 * 1024        # 1 MB text
MAX_FILE_SIZE = 25 * 1024 * 1024      # 25 MB (base64 friendly)
MAX_USERS = 20
MAX_GROUPS = 50

# Admin hard-coded reset password
ADMIN_RESET_PASSWORD = "4593"

# Default global group id
GLOBAL_GROUP_ID = "global"

# Protocol version
PROTOCOL_VERSION = "1.1"
