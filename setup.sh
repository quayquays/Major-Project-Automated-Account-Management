#!/bin/bash

CONFIG_FILE="/etc/dormant.conf"
USER_EMAIL_FILE="/etc/user_emails.conf"
GMAIL_CONFIG_FILE="/etc/gmail.conf"

SCRIPT_NAME="dormant.sh"
SERVER_SCRIPT_NAME="server.py"
TARGET_PATH="/usr/local/bin/$SCRIPT_NAME"
SERVER_TARGET="/usr/local/bin/$SERVER_SCRIPT_NAME"
LOCAL_PATH="$(dirname "$0")/$SCRIPT_NAME"
SERVER_LOCAL_PATH="$(dirname "$0")/$SERVER_SCRIPT_NAME"

LOG_DIR="/var/log"
DORMANT_LOG="$LOG_DIR/dormant.log"
SERVER_LOG="$LOG_DIR/server.log"
SYSTEMD_SERVICE="/etc/systemd/system/serverpy.service"

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

sudo apt update

install_if_missing "dialog"
install_if_missing "sendemail"
install_if_missing "libio-socket-ssl-perl"
install_if_missing "python3-pip"
install_if_missing "python3-flask"
install_if_missing "dbus-x11"  # ✅ Fix for gnome-terminal GUI launch

echo ""
echo "----------------------------------------"
echo "CONFIGURATION FILES"
echo "----------------------------------------"

# Main config
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<EOL | sudo tee "$CONFIG_FILE" > /dev/null
# configuration file of dormant accounts ( USER and SERVICES )

DORMANT_USERACCOUNT_DURATION=70
DORMANT_SERVICEACCOUNT_DURATION=30
DORMANT_PASSWORD_EXPIRY_DURATION=60
DORMANT_CRON_SCHEDULE="*/2 * * * *"
EOL
    echo "Created config: $CONFIG_FILE"
else
    echo "$CONFIG_FILE already exists. Skipping creation."
fi

# Email mapping
if [[ ! -f "$USER_EMAIL_FILE" ]]; then
    echo "# username=email@example.com" | sudo tee "$USER_EMAIL_FILE" > /dev/null
    echo "# Example: user01=example@gmail.com" | sudo tee -a "$USER_EMAIL_FILE" > /dev/null
    echo "Created email mapping: $USER_EMAIL_FILE"
else
    echo "$USER_EMAIL_FILE already exists. Skipping creation."
fi

# Gmail credentials config (lowercase variables)
if [[ ! -f "$GMAIL_CONFIG_FILE" ]]; then
    cat <<EOL | sudo tee "$GMAIL_CONFIG_FILE" > /dev/null
# Gmail SMTP credentials for sending alerts

from_email=youremail@gmail.com
login_email=youremail@gmail.com
app_password=your_app_password
EOL
    sudo chmod 600 "$GMAIL_CONFIG_FILE"
    echo "Created Gmail config: $GMAIL_CONFIG_FILE"
else
    echo "$GMAIL_CONFIG_FILE already exists. Skipping creation."
fi

echo ""
echo "----------------------------------------"
echo "INSTALLING SCRIPTS"
echo "----------------------------------------"

# Install dormant.sh
if [[ -f "$LOCAL_PATH" ]]; then
    sudo cp "$LOCAL_PATH" "$TARGET_PATH"
    sudo chmod +x "$TARGET_PATH"
    echo "Installed: $TARGET_PATH"
else
    echo "ERROR: $SCRIPT_NAME not found in $(dirname "$0")"
    exit 1
fi

# Install server.py
if [[ -f "$SERVER_LOCAL_PATH" ]]; then
    sudo cp "$SERVER_LOCAL_PATH" "$SERVER_TARGET"
    sudo chmod +x "$SERVER_TARGET"
    echo "Installed: $SERVER_TARGET"
else
    echo "ERROR: $SERVER_SCRIPT_NAME not found in $(dirname "$0")"
    exit 1
fi

# Ensure logs exist
sudo touch "$DORMANT_LOG" "$SERVER_LOG"
sudo chmod 666 "$DORMANT_LOG" "$SERVER_LOG"

# Load config
source "$CONFIG_FILE"

if [[ -z "$DORMANT_CRON_SCHEDULE" ]]; then
    echo "ERROR: DORMANT_CRON_SCHEDULE not set in $CONFIG_FILE"
    exit 1
fi

echo ""
echo "----------------------------------------"
echo "SETTING UP CRON (dormant.sh)"
echo "----------------------------------------"

# Setup cron (dormant.sh only)
(crontab -l 2>/dev/null | grep -v "$TARGET_PATH" ; echo "$DORMANT_CRON_SCHEDULE bash $TARGET_PATH >> $DORMANT_LOG 2>&1") | crontab -
echo "Cron installed for dormant.sh: $DORMANT_CRON_SCHEDULE"

echo ""
echo "----------------------------------------"
echo "SETTING UP SYSTEMD SERVICE (server.py)"
echo "----------------------------------------"

# Create systemd service for server.py
sudo tee "$SYSTEMD_SERVICE" > /dev/null <<EOF
[Unit]
Description=Flask Server Script
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SERVER_TARGET
WorkingDirectory=/usr/local/bin
StandardOutput=append:$SERVER_LOG
StandardError=append:$SERVER_LOG
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload, enable and start the service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable serverpy.service
sudo systemctl restart serverpy.service

echo ""
echo "----------------------------------------"
echo "INSTALLATION SUMMARY"
echo "----------------------------------------"
echo "Config file        : $CONFIG_FILE"
echo "User emails file   : $USER_EMAIL_FILE"
echo "Gmail config file  : $GMAIL_CONFIG_FILE"
echo "Dormant script     : $TARGET_PATH"
echo "Server script      : $SERVER_TARGET"
echo "Cron schedule      : $DORMANT_CRON_SCHEDULE"
echo "Dormant log        : $DORMANT_LOG"
echo "Server log         : $SERVER_LOG"
echo "Systemd service    : serverpy.service"

if [[ ${#INSTALLED_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    echo "Newly installed packages:"
    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        echo " - $pkg (location: $(which "$pkg" 2>/dev/null || echo 'not found'))"
    done
else
    echo ""
    echo "All required packages were already installed."
fi

echo ""
echo "----------------------------------------"
echo "SETUP COMPLETE 🎉"
echo "----------------------------------------"
