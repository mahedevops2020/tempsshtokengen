#!/bin/bash

# === CONFIGURATION ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/token_ssh.log"
DB_FILE="$SCRIPT_DIR/tokens.db"
KEY_DIR="$SCRIPT_DIR/token_keys"
AUTH_KEYS="$HOME/.ssh/authorized_keys"

# === Show Help ===
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "🛠️ Token SSH Access Tool"
    echo ""
    echo "Usage:"
    echo "  $0 [--expiry <days>]         Create a new token with expiry in days (default: 1)"
    echo "  $0 --list                    List all active tokens"
    echo "  $0 --revoke <token>          Revoke a specific token manually"
    echo "  $0 --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           Create token with 1-day expiry"
    echo "  $0 --expiry 3                Create token with 3-day expiry"
    echo "  $0 --list                    Show active tokens"
    echo "  $0 --revoke abc123ef         Revoke token 'abc123ef'"
    echo ""
    echo "🔐 All actions are logged in: $LOG_FILE"
    exit 0
fi

mkdir -p "$KEY_DIR"
touch "$DB_FILE"

# === Helper: Log Function ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# === Helper: Revoke Token ===
revoke_token() {
    TOKEN=$1
    LINE=$(grep "^$TOKEN:" "$DB_FILE" | tail -n 1)
    if [ -z "$LINE" ]; then
        echo "❌ Token not found: $TOKEN"
        exit 1
    fi

    COMMENT="token-$TOKEN"
    KEY_NAME=$(echo "$LINE" | cut -d':' -f2)
    PID=$(echo "$LINE" | cut -d':' -f4)

    # Kill the background sleep job
    if [[ "$PID" =~ ^[0-9]+$ ]] && ps -p "$PID" > /dev/null 2>&1; then
        kill "$PID" && log "⛔ Sleep job killed for token: $TOKEN"
    fi

    # Remove from DB first so cleanup block will skip
    sed -i "/^$TOKEN:/d" "$DB_FILE"

    # Safely remove from authorized_keys
    if [ -f "$AUTH_KEYS" ]; then
        grep -v "$COMMENT" "$AUTH_KEYS" > "${AUTH_KEYS}.tmp"
        if [ -f "${AUTH_KEYS}.tmp" ]; then
            mv "${AUTH_KEYS}.tmp" "$AUTH_KEYS"
        fi
    fi

    # Remove key files
    rm -f "$KEY_DIR/$KEY_NAME" "$KEY_DIR/${KEY_NAME}.pub"

    log "🧹 Token manually revoked: $TOKEN"
    echo "✅ Token revoked: $TOKEN"
    exit 0
}

# === Helper: List Active Tokens ===
list_tokens() {
    NOW=$(date +%s)
    echo "📋 Active Tokens:"
    while IFS=: read -r TOKEN KEY EXPIRY; do
        if [ "$NOW" -lt "$EXPIRY" ]; then
            EXPIRY_HUMAN=$(date -d "@$EXPIRY" '+%Y-%m-%d %H:%M:%S')
            echo "🔐 $TOKEN | Expires: $EXPIRY_HUMAN"
        fi
    done < "$DB_FILE"
    exit 0
}

# === Parse CLI Arguments ===
if [[ "$1" == "--revoke" ]]; then
    revoke_token "$2"
elif [[ "$1" == "--list" ]]; then
    list_tokens
elif [[ "$1" == "--expiry" ]]; then
    EXPIRY_DAYS="$2"
    shift 2
else
    EXPIRY_DAYS=1  # Default: 1 day
fi


# === Validate Arguments ===
VALID_FLAGS=("--expiry" "--revoke" "--list" "--help" "-h")

if [[ "$1" != "" ]]; then
    FOUND=0
    for flag in "${VALID_FLAGS[@]}"; do
        if [[ "$1" == "$flag" ]]; then
            FOUND=1
            break
        fi
    done

    if [[ "$FOUND" -eq 0 ]]; then
        echo "❌ Unknown option: $1"
        echo "Run with --help to see available options."
        exit 1
    fi
fi


# === Generate Token and Key ===
TOKEN=$(openssl rand -hex 8)
KEY_NAME="key_$TOKEN"
COMMENT="token-$TOKEN"
EXPIRY_EPOCH=$(( $(date +%s) + EXPIRY_DAYS * 86400 ))

cd "$KEY_DIR"
#ssh-keygen -f "$KEY_NAME" -N "" -C "$COMMENT" > /dev/null
ssh-keygen -t rsa -b 2048 -f "$KEY_NAME" -N "" -C "$COMMENT" -q > /dev/null
cat "${KEY_NAME}.pub" >> "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
echo "$TOKEN:$KEY_NAME:$EXPIRY_EPOCH" >> "$DB_FILE"
log "🔐 Token created: $TOKEN | Expiry: $EXPIRY_DAYS days"


# === Schedule Cleanup ===
TMP_PID_FILE=$(mktemp)

(
    # Start sleep and capture its PID
    sleep $((EXPIRY_DAYS * 86400)) &
    echo $! > "$TMP_PID_FILE"

    # Wait for the sleep to finish
    wait $(cat "$TMP_PID_FILE")

    # Cleanup
    grep -v "$COMMENT" "$AUTH_KEYS" > "${AUTH_KEYS}.tmp"
    mv "${AUTH_KEYS}.tmp" "$AUTH_KEYS"
    rm -f "$KEY_DIR/$KEY_NAME" "$KEY_DIR/${KEY_NAME}.pub"
    sed -i "/^$TOKEN:/d" "$DB_FILE"
    log "🧹 Token auto-revoked: $TOKEN"
) &

# Now read the actual sleep PID
SLEEP_PID=$(cat "$TMP_PID_FILE")
rm -f "$TMP_PID_FILE"


sed -i "/^$TOKEN:/d" "$DB_FILE"
echo "$TOKEN:$KEY_NAME:$EXPIRY_EPOCH:$SLEEP_PID" >> "$DB_FILE"

# === Show Connection Info ===
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "🔐 Token: $TOKEN"
echo "📁 Private key: $KEY_DIR/$KEY_NAME"
echo "🕒 Expires in: $EXPIRY_DAYS day(s)"
echo "📡 SSH Command:"
#echo "ssh -i $KEY_DIR/$KEY_NAME $(whoami)@$IP"
# Output copy-paste block for colleague
echo -e "\n📋 Share this block with your colleague:\n"
printf "cat>/tmp/temp_token.pem<<'EOF'\n%s\nEOF\nchmod 600 /tmp/temp_token.pem\nssh -i /tmp/temp_token.pem %s\n" "$(cat $KEY_DIR/$KEY_NAME)" "$(whoami)@$IP"