#!/bin/bash

# Load configuration
source /etc/dormant.conf

# Email config file
EMAIL_CONFIG_FILE="/etc/user_emails.conf"
if [[ -f "$EMAIL_CONFIG_FILE" ]]; then
    source "$EMAIL_CONFIG_FILE"
fi

# Load Gmail credentials from config
GMAIL_CONFIG_FILE="/etc/gmail.conf"
if [[ -f "$GMAIL_CONFIG_FILE" ]]; then
    source "$GMAIL_CONFIG_FILE"
else
    echo "ERROR: $GMAIL_CONFIG_FILE not found. Please create it with Gmail credentials."
    exit 1
fi

# Load Sysadmin name from config file
SYSADMIN_NAME_FILE="/etc/sysadmin_name.conf"
if [[ -f "$SYSADMIN_NAME_FILE" ]]; then
    source "$SYSADMIN_NAME_FILE"  # This will set sysadmin_name variable
    SYSADMIN_NAME="$sysadmin_name"  # Assign it to your variable
else
    SYSADMIN_NAME="System Administrator"
fi

# File containing cybersecurity personnel (name + email)
CYBERSEC_FILE="/etc/cybersecurity_professionals.conf"

OPT_IN_FILE="/etc/dormant_opt_in.conf"
touch "$OPT_IN_FILE"

# Log files
EMAIL_DEACTIVATION_LOG="/var/log/dormant/deactivated_users.log"
MANUAL_DEACTIVATION_LOG="/var/log/manual_deactivation.log"
AUTO_DEACTIVATION_LOG="/var/log/automated_deactivation.log"
REACTIVATION_LOG="/var/log/reactivation.log"

# --- Load users reactivated within last 24 hours to skip dormant detection ---
declare -A recently_reactivated_users=()
if [[ -f "$REACTIVATION_LOG" ]]; then
    today_ts=$(date +%s)
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ -\ Reactivated\ user:\ ([^[:space:]]+) ]]; then
            reactivation_time="${BASH_REMATCH[1]}"
            user="${BASH_REMATCH[2]}"
            reactivation_ts=$(date -d "$reactivation_time" +%s)
            diff_sec=$(( today_ts - reactivation_ts ))
            if (( diff_sec < 86400 )); then
                recently_reactivated_users["$user"]=1
            fi
        fi
    done < "$REACTIVATION_LOG"
fi

get_user_email() {
    local user=$1
    grep "^${user}=" "$EMAIL_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2
}

send_email_to_user() {
    local user=$1
    local email=$2
    local days_inactive=$3
    local server_url="http://ngrok_url"  # Replace with actual ngrok/public IP

    local confirm_url="${server_url}/confirm?user=${user}&response=yes"
    local deny_url="${server_url}/deactivate/${user}?response=no"  # New "No" URL for deactivation

    local subject="⚠️ Your account will be deactivated in 7 days"
    local body="Hi $user,\n\nOur records show your account has been inactive for $days_inactive days.\n\nYour account will be deactivated in 7 days if no action is taken.\n\nWould you like to keep your account?\n\nYES: $confirm_url\nNO: $deny_url\n\nThank you."

    sendemail -f "$from_email" \
              -t "$email" \
              -u "$subject" \
              -m "$body" \
              -s smtp.gmail.com:587 \
              -o tls=yes -xu "$login_email" -xp "$app_password"
}

check_user_account() {
    user_account=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
}

detect_dormant_user() {
    dormant_detected_user=()
    about_to_be_dormant_user=()
    dormant_email_log=()
    mkdir -p "$(dirname "$AUTO_DEACTIVATION_LOG")"
    touch "$AUTO_DEACTIVATION_LOG"

    for user in $user_account; do
        # Skip if user was recently reactivated (within last 24h)
        if [[ -n "${recently_reactivated_users[$user]}" ]]; then
            continue
        fi

        # Check if user has opted in to keep account
        if grep -q "^$user=" "$OPT_IN_FILE"; then
            optin_date=$(grep "^$user=" "$OPT_IN_FILE" | cut -d= -f2)
            optin_ts=$(date -d "$optin_date" +%s 2>/dev/null)
            today_ts=$(date +%s)
            days_since_optin=$(( (today_ts - optin_ts) / 86400 ))

            if [ "$days_since_optin" -lt "$DORMANT_USERACCOUNT_DURATION" ]; then
                continue  # Skip user if they opted in recently
            fi
        fi

        lastlogin_raw=$(lastlog -u "$user" | awk 'NR==2')

        if [[ "$lastlogin_raw" == *"Never logged in"* ]]; then
            continue
        fi

        last_login_date=$(echo "$lastlogin_raw" | awk '{print $4, $5, $6}')

        if [[ -n "$last_login_date" ]]; then
            if last_login_ts=$(date -d "$last_login_date" +%s 2>/dev/null); then
                today_ts=$(date +%s)
                diff_days=$(( (today_ts - last_login_ts) / 86400 ))

                if [ "$diff_days" -eq $((DORMANT_USERACCOUNT_DURATION - 7)) ]; then
                    email=$(get_user_email "$user")
                    if [[ -n "$email" ]]; then
                        send_email_to_user "$user" "$email" "$diff_days"
                        dormant_email_log+=("Email sent to $user ($email)")
                    else
                        dormant_email_log+=("⚠️ No email found for $user")
                    fi
                    about_to_be_dormant_user+=("$user")
                fi

                if [ "$diff_days" -ge "$DORMANT_USERACCOUNT_DURATION" ]; then
                    dormant_detected_user+=("$user")

                    # Check if account is already locked before locking
                    if ! passwd -S "$user" | grep -q ' L '; then
                        usermod -L "$user"
                    fi

                    # Check if shell is already /sbin/nologin before changing
                    current_shell=$(getent passwd "$user" | cut -d: -f7)
                    if [[ "$current_shell" != "/sbin/nologin" ]]; then
                        usermod -s /sbin/nologin "$user"
                    fi

                    # Log deactivation with timestamp
                    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                    echo "$timestamp - Deactivated user: $user (inactive for $diff_days days)" >> "$AUTO_DEACTIVATION_LOG"
                fi
            fi
        fi
    done
}

check_password_expiry() {
    password_expired_user=()

    for user in $user_account; do
        last_change_line=$(chage -l "$user" 2>/dev/null | grep "Last password change")
        last_change_date=$(echo "$last_change_line" | awk -F: '{print $2}' | xargs)

        if [[ "$last_change_date" == "never" ]] || [[ -z "$last_change_date" ]]; then
            continue
        fi

        if last_change_ts=$(date -d "$last_change_date" +%s 2>/dev/null); then
            today_ts=$(date +%s)
            diff_days=$(( (today_ts - last_change_ts) / 86400 ))

            if [ "$diff_days" -ge "$DORMANT_PASSWORD_EXPIRY_DURATION" ]; then
                password_expired_user+=("$user")
            fi
        fi
    done
}

generate_report() {
    REPORT_DIR="/dormant_reports"
    mkdir -p "$REPORT_DIR"

    human_readable_time=$(date "+%d %B %Y %H:%M")
    safe_filename_time=$(date "+%d_%b_%Y_%I-%M_%p")

    report_file="$REPORT_DIR/dormant_report_${safe_filename_time}.txt"

    today_date=$(date '+%Y-%m-%d')

    echo "---------------------------------------------------------------------------" > "$report_file"
    echo "Dormant User Account Report 📜" >> "$report_file"
    echo "Generated on: $human_readable_time" >> "$report_file"
    echo "Report generated by: $SYSADMIN_NAME" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"

    # 1. Deactivated through email
    echo "Users Deactivated via Email Link 🚫" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [[ -s "$EMAIL_DEACTIVATION_LOG" ]]; then
        grep "^$today_date" "$EMAIL_DEACTIVATION_LOG" | sort -u | tac | head -n 20 >> "$report_file" || echo "No users deactivated via email today." >> "$report_file"
    else
        echo "No users deactivated via email." >> "$report_file"
    fi
    echo >> "$report_file"

    # 2. Deactivated Manually
    echo "Users Manually Deactivated 🛠️" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [[ -s "$MANUAL_DEACTIVATION_LOG" ]]; then
        grep "^$today_date" "$MANUAL_DEACTIVATION_LOG" | sort -u | tac | head -n 20 >> "$report_file" || echo "No manual deactivations recorded today." >> "$report_file"
    else
        echo "No manual deactivations recorded." >> "$report_file"
    fi
    echo >> "$report_file"

    # 3. Deactivated Automatically
    echo "Users Automatically Deactivated 🤖" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [[ -s "$AUTO_DEACTIVATION_LOG" ]]; then
        grep "^$today_date" "$AUTO_DEACTIVATION_LOG" | sort -u | tac | head -n 20 >> "$report_file" || echo "No automatic deactivations recorded today." >> "$report_file"
    else
        echo "No automatic deactivations recorded." >> "$report_file"
    fi
    echo >> "$report_file"

    # 4. Reactivated Users 🔄
    echo "Users Reactivated ♻️" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [[ -s "$REACTIVATION_LOG" ]]; then
        grep "^$today_date" "$REACTIVATION_LOG" | sort -u | tac | head -n 20 >> "$report_file" || echo "No reactivations recorded today." >> "$report_file"
    else
        echo "No reactivations recorded." >> "$report_file"
    fi
    echo >> "$report_file"

    # 5. Users Approaching Dormancy
    echo "Users Approaching Dormancy ⏳ (=$((DORMANT_USERACCOUNT_DURATION - 7)) days)" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [ ${#about_to_be_dormant_user[@]} -eq 0 ]; then
        echo "No users approaching dormancy." >> "$report_file"
    else
        count=1
        for user in "${about_to_be_dormant_user[@]}"; do
            echo "$count. $user"
            ((count++))
        done >> "$report_file"
    fi
    echo >> "$report_file"

    # 6. Email Notifications Sent
    echo "Email Notifications Sent 📧" >> "$report_file"
    echo "---------------------------------------------------------------------------" >> "$report_file"
    if [ ${#dormant_email_log[@]} -eq 0 ]; then
        echo "No email notifications sent during this run." >> "$report_file"
    else
        for line in "${dormant_email_log[@]}"; do
            echo "$line"
        done >> "$report_file"
    fi

    echo "---------------------------------------------------------------------------" >> "$report_file"

    echo "$report_file"
}

send_report_to_cybersec() {
    local report_path=$1

    if [[ ! -f "$CYBERSEC_FILE" ]]; then
        echo "Cybersecurity personnel file not found: $CYBERSEC_FILE"
        return
    fi

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Extract name and email from format: Name <email>
        if [[ "$line" =~ ^(.+)\ \<(.+@.+)\>$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local email="${BASH_REMATCH[2]}"

            local subject="Dormant Accounts & Password Expiry Report"
            local body="Hi $name,\n\nThis report is provided by $SYSADMIN_NAME.\n\nPlease find the attached report regarding dormant accounts and password expiries.\n\nThank you."

            sendemail -f "$from_email" \
                      -t "$email" \
                      -u "$subject" \
                      -m "$body" \
                      -s smtp.gmail.com:587 \
                      -o tls=yes -xu "$login_email" -xp "$app_password" \
                      -a "$report_path"

            echo "Report sent to $name <$email>"
        else
            echo "Invalid line in $CYBERSEC_FILE: $line"
        fi
    done < "$CYBERSEC_FILE"
}

# --- MAIN RUN ---

check_user_account
detect_dormant_user
check_password_expiry

report_file=$(generate_report)

send_report_to_cybersec "$report_file"
