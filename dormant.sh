#!/bin/bash

# Load configuration
source /etc/dormant.conf

# Validate config values
if [ -z "$DORMANT_USERACCOUNT_DURATION" ] || [ -z "$DORMANT_SERVICEACCOUNT_DURATION" ] || [ -z "$DORMANT_PASSWORD_EXPIRY_DURATION" ]; then
    echo "Error: Config file missing required parameters."
    exit 1
fi

# Collect user accounts (UID >= 1000)
check_user_account() {
    user_account=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
}

# Detect dormant users
detect_dormant_user() {
    dormant_detected_user=()

    for user in $user_account; do
        lastlogin_raw=$(lastlog -u "$user" | awk 'NR==2')

        if [[ "$lastlogin_raw" == *"Never logged in"* ]]; then
            continue
        fi

        last_login_date=$(echo "$lastlogin_raw" | awk '{print $4, $5, $6}')

        if [[ -n "$last_login_date" ]]; then
            if last_login_ts=$(date -d "$last_login_date" +%s 2>/dev/null); then
                today_ts=$(date +%s)
                diff_days=$(( (today_ts - last_login_ts) / 86400 ))

                if [ "$diff_days" -ge "$DORMANT_USERACCOUNT_DURATION" ]; then
                    dormant_detected_user+=("$user")
                fi
            fi
        fi
    done
}

# Check password expiry
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

# Generate report
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
    } > "$report_file"

    echo "Report generated at: $report_file"
}

# Run
check_user_account
detect_dormant_user
check_password_expiry
generate_report
