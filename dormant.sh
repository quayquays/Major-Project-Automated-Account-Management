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
    SYSADMIN_NAME=$(head -n 1 "$SYSADMIN_NAME_FILE" | xargs)
else
    SYSADMIN_NAME="System Administrator"
fi

# File containing cybersecurity personnel (name + email)
CYBERSEC_FILE="/etc/cybersecurity_professionals.conf"

OPT_IN_FILE="/etc/dormant_opt_in.conf"
touch "$OPT_IN_FILE"

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

    for user in $user_account; do
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

    {
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users & Password Expiry Report 📜"
        echo "Generated on: $human_readable_time"
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users 👥 (>= $DORMANT_USERACCOUNT_DURATION days)"
        echo "---------------------------------------------------------------------------"

        if [ ${#dormant_detected_user[@]} -eq 0 ]; then
            echo "No dormant users found."
        else
            count=1
            for user in "${dormant_detected_user[@]}"; do
                echo "$count. $user"
                ((count++))
            done
        fi

        echo "---------------------------------------------------------------------------"
        echo "Users Approaching Dormancy ⏳ (=$((DORMANT_USERACCOUNT_DURATION - 7)) days)"
        echo "---------------------------------------------------------------------------"

        if [ ${#about_to_be_dormant_user[@]} -eq 0 ]; then
            echo "No users approaching dormancy."
        else
            count=1
            for user in "${about_to_be_dormant_user[@]}"; do
                echo "$count. $user"
                ((count++))
            done
        fi

        echo "---------------------------------------------------------------------------"
        echo "Users With Expired Passwords 🔒"
        echo "---------------------------------------------------------------------------"

        if [ ${#password_expired_user[@]} -eq 0 ]; then
            echo "No users with expired passwords."
        else
            count=1
            for user in "${password_expired_user[@]}"; do
                echo "$count. $user (password exceeded $DORMANT_PASSWORD_EXPIRY_DURATION days)"
                ((count++))
            done
        fi

        echo "---------------------------------------------------------------------------"
        echo "Email Notifications Sent 📧"
        echo "---------------------------------------------------------------------------"

        if [ ${#dormant_email_log[@]} -eq 0 ]; then
            echo "No email notifications were sent during this run."
        else
            for line in "${dormant_email_log[@]}"; do
                echo "$line"
            done
        fi

        echo "---------------------------------------------------------------------------"
    } > "$report_file"

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

            # Compose subject and personalized message body
            local subject="Dormant Accounts & Password Expiry Report"
            local body="Hi $name,\n\nThis report is provided by $SYSADMIN_NAME.\n\nPlease find the attached report regarding dormant accounts and password expiries.\n\nThank you."

            # Send the email with report attached (using sendemail)
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
