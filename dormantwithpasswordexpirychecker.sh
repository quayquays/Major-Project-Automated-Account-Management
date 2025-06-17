#!/bin/bash

# Load configuration
source /etc/dormant.conf

# Validate config values
if [ -z "$DORMANT_USERACCOUNT_DURATION" ] || [ -z "$DORMANT_SERVICEACCOUNT_DURATION" ] || [ -z "$DORMANT_PASSWORD_EXPIRY_DURATION" ]; then
    echo "Error: Config file missing required parameters."
    exit 1
fi

echo "Duration of User account: $DORMANT_USERACCOUNT_DURATION days"
echo "Duration of Service account: $DORMANT_SERVICEACCOUNT_DURATION days"
echo "Password expiry duration: $DORMANT_PASSWORD_EXPIRY_DURATION days"

# Collect user accounts (UID >= 1000)
check_user_account() {
    user_account=$(grep '^[^:]*:[^:]*:[1-9][0-9]\{3,\}:' /etc/passwd | cut -d: -f1)
}

# Detect dormant users (inactive > threshold)
detect_dormant_user() {
    dormant_detected_user=()

    for user in $user_account; do
        lastlogin=$(lastlog -u "$user" | awk 'NR==2')

        if [[ -z "$lastlogin" ]] || [[ "$lastlogin" == *"Never logged in"* ]]; then
            continue
        fi

        last_login_date=$(echo "$lastlogin" | awk '{print $4, $5, $6}')

        if [[ -n "$last_login_date" ]]; then
            if last_login_ts=$(date -d "$last_login_date" +%s 2>/dev/null); then
                today_ts=$(date +%s)
                difference=$(( (today_ts - last_login_ts) / 86400 ))

                echo "User $user last logged in on: $last_login_date ($difference days ago)"

                if [ "$difference" -ge "$DORMANT_USERACCOUNT_DURATION" ]; then
                    dormant_detected_user+=("$user")
                fi
            else
                echo "Could not parse last login date for user $user: $last_login_date"
            fi
        else
            echo "No valid last login date for user $user."
        fi
    done

    if [[ ${#dormant_detected_user[@]} -gt 0 ]]; then
        echo "Dormant users detected: ${dormant_detected_user[*]}"
    else
        echo "No dormant users detected."
    fi
}

# Check password expiry (unchanged > threshold)
check_password_expiry() {
    password_expired_user=()

    for user in $user_account; do
        last_change_ts=$(chage -l "$user" | grep "Last password change" | awk -F: '{print $2}' | xargs -I{} date -d "{}" +%s 2>/dev/null)
        today_ts=$(date +%s)

        if [[ -n "$last_change_ts" ]]; then
            difference=$(( (today_ts - last_change_ts) / 86400 ))
            echo "User $user last changed password: $difference days ago"

            if [ "$difference" -ge "$DORMANT_PASSWORD_EXPIRY_DURATION" ]; then
                password_expired_user+=("$user")
                echo "⚠️  User $user must change password (exceeded $DORMANT_PASSWORD_EXPIRY_DURATION days)."
                # Optional: force expiry
                # passwd -e "$user"
            fi
        else
            echo "Could not retrieve last password change date for user $user"
        fi
    done
}

# Generate final report
generate_report() {
    REPORT_DIR="/dormant_reports"
    [ ! -d "$REPORT_DIR" ] && mkdir -p "$REPORT_DIR"

    timestamp=$(date "+%Y%m%d_%H%M%S")
    report_file="$REPORT_DIR/dormant_report_$timestamp.txt"

    {
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users & Password Expiry Report 📜 - $timestamp"
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users 👥"
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
    } >> "$report_file"

    echo "Report generated at: $report_file"
}

# Run sequence
check_user_account
detect_dormant_user
check_password_expiry
generate_report
