#!/bin/bash

##SCRIPT TO UPDATE THE CRON CONFIGURATIONS

CONFIG_FILE="/etc/dormant.conf"
TARGET_SCRIPT="/usr/local/bin/dormant.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found at $CONFIG_FILE ! Please set it up using setup.sh "
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"


if [[ -z "$DORMANT_CRON_SCHEDULE" ]]; then
    echo "DORMANT_CRON_SCHEDULE not set in config.Please create a variable name DORMANT_CRON_SCHEDULE and assign a schedule for the cron job."
    exit 1
fi

# Remove old entry and set new one
(crontab -l 2>/dev/null | grep -v "$TARGET_SCRIPT" ; echo "$DORMANT_CRON_SCHEDULE bash $TARGET_SCRIPT") | crontab -

echo "✅ Cron schedule set to: $DORMANT_CRON_SCHEDULE"
