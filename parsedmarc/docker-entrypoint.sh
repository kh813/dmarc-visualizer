#!/bin/sh
set -e

CONFIG_FILE="/etc/parsedmarc.ini"

# If config file does not exist, generate one from environment variables
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating $CONFIG_FILE from environment variables..."
    cat <<EOF > "$CONFIG_FILE"
[general]
save_aggregate = True
save_forensic = True
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
