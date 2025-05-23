#!/bin/bash

CONFIG_FILE="/etc/dormant.conf"
SCRIPT_NAME="dormant.sh"
TARGET_PATH="/usr/local/bin/$SCRIPT_NAME"
LOCAL_PATH="$(dirname "$0")/$SCRIPT_NAME"

# Create config file if it doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<EOL | sudo tee "$CONFIG_FILE" > /dev/null
DORMANT_USERACCOUNT_DURATION=70
DORMANT_SERVICEACCOUNT_DURATION=30
DORMANT_CRON_SCHEDULE="*/2 * * * *"
EOL
    echo "Config created at $CONFIG_FILE"
else
    echo "$CONFIG_FILE already exists, skipping creation."
fi

# Move dormant.sh script to /usr/local/bin and make executable
if [[ -f "$LOCAL_PATH" ]]; then
    sudo cp "$LOCAL_PATH" "$TARGET_PATH"
    sudo chmod +x "$TARGET_PATH"
    echo "Moved $SCRIPT_NAME to $TARGET_PATH and made executable"
else
    echo "Error: $SCRIPT_NAME not found in script directory."
    exit 1
fi

# Source config and setup cron job
source "$CONFIG_FILE"

if [[ -z "$DORMANT_CRON_SCHEDULE" ]]; then
    echo "Error: DORMANT_CRON_SCHEDULE not set in $CONFIG_FILE"
    exit 1
fi

# Add the cron job, replacing any previous entry for dormant.sh
(crontab -l 2>/dev/null | grep -v "$TARGET_PATH" ; echo "$DORMANT_CRON_SCHEDULE bash $TARGET_PATH") | crontab -

echo "Cron job installed: $DORMANT_CRON_SCHEDULE bash $TARGET_PATH"
echo "Setup complete! Edit config at $CONFIG_FILE if needed."
