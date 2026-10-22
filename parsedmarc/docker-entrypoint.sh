#!/bin/sh
set -e

RUNTIME_CONFIG="/etc/parsedmarc.ini"
USER_CONFIG="/config/parsedmarc.ini"

if [ -f "$USER_CONFIG" ]; then
    echo "Found user configuration at $USER_CONFIG."
    cp "$USER_CONFIG" "$RUNTIME_CONFIG"

    # Check for legacy [elasticsearch] section
    if grep -q "\[elasticsearch\]" "$RUNTIME_CONFIG"; then
        echo "[!] WARNING: Legacy [elasticsearch] section detected in parsedmarc.ini."
        echo "    Elasticsearch is replaced with PostgreSQL. Disabling [elasticsearch] in runtime config..."
        sed -i 's/\[elasticsearch\]/\[_disabled_elasticsearch\]/g' "$RUNTIME_CONFIG"
    fi

    # Append [postgresql] section if missing
    if ! grep -q "\[postgresql\]" "$RUNTIME_CONFIG"; then
        echo "[+] Appending PostgreSQL connection settings from environment to runtime config..."
        cat <<EOF >> "$RUNTIME_CONFIG"

[postgresql]
host = ${POSTGRES_HOST:-postgres}
port = ${POSTGRES_PORT:-5432}
database = ${POSTGRES_DB:-dmarc}
user = ${POSTGRES_USER:-parsedmarc}
password = ${POSTGRES_PASSWORD:-parsedmarc_password}
EOF
    fi
else
    echo "No custom config found at $USER_CONFIG. Generating default configuration from environment..."
    cat <<EOF > "$RUNTIME_CONFIG"
[general]
save_aggregate = True
save_forensic = True
save_smtp_tls = True
output = /output/

[postgresql]
host = ${POSTGRES_HOST:-postgres}
port = ${POSTGRES_PORT:-5432}
database = ${POSTGRES_DB:-dmarc}
user = ${POSTGRES_USER:-parsedmarc}
password = ${POSTGRES_PASSWORD:-parsedmarc_password}
EOF
fi

# Execute CMD or passed arguments
exec "$@"
