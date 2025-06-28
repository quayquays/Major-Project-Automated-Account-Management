#!/bin/bash

CONFIG_FILE="/etc/dormant.conf"
USER_EMAIL_FILE="/etc/user_emails.conf"
SCRIPT_NAME="dormant.sh"
TARGET_PATH="/usr/local/bin/$SCRIPT_NAME"
LOCAL_PATH="$(dirname "$0")/$SCRIPT_NAME"

INSTALLED_PACKAGES=()

# Abort early if dpkg is locked or broken
if sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null || sudo fuser /var/lib/dpkg/lock &>/dev/null; then
    echo "ERROR: Another package manager is running. Please wait or kill the process."
    exit 1
fi

if sudo dpkg --audit | grep -q "packages are only half installed/configured"; then
    echo "ERROR: dpkg is in a broken state. Please run: sudo dpkg --configure -a"
    exit 1
fi

# Function to install packages safely
install_if_missing() {
    local pkg="$1"

    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "Installing $pkg..."
        if sudo apt install -y "$pkg"; then
            INSTALLED_PACKAGES+=("$pkg")
        else
            echo "WARNING: Failed to install $pkg. Please check your network or install it manually."
        fi
    else
        echo "$pkg already installed."
    fi
}

echo ""
echo "----------------------------------------"
echo "DEPENDENCY CHECK & INSTALLATION"
echo "----------------------------------------"

# Update apt once
sudo apt update

# Install required tools
install_if_missing "dialog"
install_if_missing "sendemail"
install_if_missing "libio-socket-ssl-perl"

echo ""
echo "----------------------------------------"
echo "CONFIGURATION FILES"
echo "----------------------------------------"

# Create main config file if it doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<EOL | sudo tee "$CONFIG_FILE" > /dev/null
# configuration file of dormant accounts ( USER and SERVICES )

# Specify the number of days for dormant user accounts
DORMANT_USERACCOUNT_DURATION=70  # Example: 70 days

# Specify the number of days for dormant service accounts
DORMANT_SERVICEACCOUNT_DURATION=30  # Example: 30 days

# Specify the number of days for password expiry
DORMANT_PASSWORD_EXPIRY_DURATION=60  # Example: 60 days

# Cron schedule for running dormant.sh (min hour dom month dow)
# Example: 0 2 * * * = every day at 2:00 AM
DORMANT_CRON_SCHEDULE="*/2 * * * *"
EOL
    echo "Created config: $CONFIG_FILE"
else
    echo "$CONFIG_FILE already exists. Skipping creation."
fi

# Create user_emails.conf if it doesn't exist
if [[ ! -f "$USER_EMAIL_FILE" ]]; then
    echo "# username=email@example.com" | sudo tee "$USER_EMAIL_FILE" > /dev/null
    echo "# Example: user01=example@gmail.com" | sudo tee -a "$USER_EMAIL_FILE" > /dev/null
    echo "Created email mapping: $USER_EMAIL_FILE"
else
    echo "$USER_EMAIL_FILE already exists. Skipping creation."
fi

echo ""
echo "----------------------------------------"
echo "SCRIPT INSTALLATION"
echo "----------------------------------------"

# Move the dormant.sh script and make it executable
if [[ -f "$LOCAL_PATH" ]]; then
    sudo cp "$LOCAL_PATH" "$TARGET_PATH"
    sudo chmod +x "$TARGET_PATH"
    echo "Installed script: $TARGET_PATH"
else
    echo "ERROR: $SCRIPT_NAME not found in $(dirname "$0")"
    exit 1
fi

# Source config values
source "$CONFIG_FILE"

# Validate cron config
if [[ -z "$DORMANT_CRON_SCHEDULE" ]]; then
    echo "ERROR: DORMANT_CRON_SCHEDULE not set in $CONFIG_FILE"
    exit 1
fi

# Setup cron job (avoids duplicates)
(crontab -l 2>/dev/null | grep -v "$TARGET_PATH" ; echo "$DORMANT_CRON_SCHEDULE bash $TARGET_PATH") | crontab -

echo "Installed cron job: $DORMANT_CRON_SCHEDULE bash $TARGET_PATH"

echo ""
echo "----------------------------------------"
echo "INSTALLATION SUMMARY"
echo "----------------------------------------"

echo "Config file      : $CONFIG_FILE"
echo "User emails file : $USER_EMAIL_FILE"
echo "Script location  : $TARGET_PATH"
echo "Cron schedule    : $DORMANT_CRON_SCHEDULE"

echo ""
echo "-------------------- Required Packages --------------------"
echo "This tool requires the following packages, which were installed if missing:"
echo " - dialog"
echo " - sendemail"
echo " - libio-socket-ssl-perl"

if [[ ${#INSTALLED_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    echo "The following packages were newly installed on this system:"
    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        echo " - $pkg (location: $(which "$pkg" 2>/dev/null || echo 'not found'))"
    done
else
    echo ""
    echo "All required packages were already installed."
fi

echo ""
echo "----------------------------------------"
echo "SETUP COMPLETE"
echo "----------------------------------------"
