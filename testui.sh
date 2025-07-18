!/bin/bash

# Paths and temp files
TMPFILE="/tmp/dormant_ui_tmp.$$"
REPORT_DIR="/dormant_reports"          # Set your actual report directory here
EMAIL_CONF="/etc/user_emails.conf"       # Set your email config file path here
CONFIG_FILE="/etc/dormant.conf"       # Your config file with dormancy variables
TARGET_SCRIPT="/usr/local/bin/dormant.sh" # Your main script that cron calls

# -------- main menu --------
main_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "Dormant User Management UI" \
            --title "Main Menu" \
            --menu "Choose a category:" 15 50 5 \
            1 "User Management" \
            2 "System Configuration" \
            3 "Reports" \
            4 "Account Expiry" \
            5 "Exit" \
            3>&1 1>&2 2>&3)

        case $CHOICE in
            1) user_management_menu ;;
            2) system_configuration_menu ;;
            3) reports_menu ;;
            4) set_expiry ;;
            5) clear; break ;;
            *) clear; break ;;
        esac
    done
}

# -------- User Management Submenu --------
user_management_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "User Management" \
            --title "User Management Menu" \
            --menu "Select an option:" 15 50 5 \
            1 "Create User Account" \
            2 "Update Email Address" \
            3 "Edit User Information" \
            4 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case $CHOICE in
            1) create_user ;;
            2) update_email ;;
            3) edit_existing_user ;;
            4) break ;;
            *) break ;;
        esac
    done
}

# -------- System Configuration Submenu --------
system_configuration_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "System Configuration" \
            --title "System Configuration Menu" \
            --menu "Select an option:" 15 60 5 \
            1 "Update System Configuration" \
            2 "Update Gmail Credentials (Email & App Password)" \
            3 "Update ngrok URL Manually" \
            4 "Generate New ngrok URL and Update" \
            5 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case $CHOICE in
            1) update_config ;;
            2) update_gmail_credentials_ui ;;
            3) update_server_url_ui ;;
            4) generate_new_ngrok_url ;;
            5) break ;;
            *) break ;;
        esac
    done
}

# -------- view reports --------
# New: Reports Menu with extra options
# -------- Reports Menu with extra options --------
reports_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "Reports Management" \
            --title "Reports Menu" \
            --menu "Select an option:" 15 60 5 \
            1 "View Dormant Reports" \
            2 "Manage Cybersecurity Professionals" \
            3 "Update Sysadmin Name" \
            4 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case $CHOICE in
            1) view_reports ;;
            2) manage_cybersecurity_professionals ;;
            3) update_sysadmin_name ;;
            4) break ;;
            *) break ;;
        esac
    done
}

view_reports() {
    declare -A FILE_MAP
    mapfile -t files < <(ls -t "$REPORT_DIR"/dormant_report_*.txt 2>/dev/null)
    if [ ${#files[@]} -eq 0 ]; then
        dialog --msgbox "No reports found in $REPORT_DIR." 10 40
        return
    fi

    dialog --inputbox "Enter date to search (e.g. 12 July 2025) or leave blank to list all:" 8 60 2> "$TMPFILE"
    search=$(<"$TMPFILE")

    OPTIONS=()
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        rawdate="${filename#dormant_report_}"
        rawdate="${rawdate%.txt}"

        # Split parts: day, month abbrev, year, time (with AM/PM)
        day=$(echo "$rawdate" | cut -d'_' -f1)
        month_abbr=$(echo "$rawdate" | cut -d'_' -f2)
        year=$(echo "$rawdate" | cut -d'_' -f3)
        time_raw=$(echo "$rawdate" | cut -d'_' -f4-)

        # Convert month abbrev to full month name
        case "$month_abbr" in
            Jan) month_full="January" ;;
            Feb) month_full="February" ;;
            Mar) month_full="March" ;;
            Apr) month_full="April" ;;
            May) month_full="May" ;;
            Jun) month_full="June" ;;
            Jul) month_full="July" ;;
            Aug) month_full="August" ;;
            Sep) month_full="September" ;;
            Oct) month_full="October" ;;
            Nov) month_full="November" ;;
            Dec) month_full="December" ;;
            *) month_full="$month_abbr" ;;
        esac

        # Time raw looks like 09-16_PM or 02-30_AM
        # Convert to 12-hour with colon and space before AM/PM
        time_formatted=$(echo "$time_raw" | sed -r 's/^([0-9]{2})-([0-9]{2})_(AM|PM)$/\1:\2 \3/')

        # Remove leading zero from hour for nicer format (e.g. 09:16 PM -> 9:16 PM)
        time_formatted=$(echo "$time_formatted" | sed -r 's/^0([1-9])/\1/')

        display="${day} ${month_full} ${year} at ${time_formatted}"

        # Filter by user search input if given (case insensitive)
        if [[ -z "$search" || "${display,,}" == *"${search,,}"* ]]; then
            OPTIONS+=("$display" "")
            FILE_MAP["$display"]="$file"
        fi
    done

    if [ ${#OPTIONS[@]} -eq 0 ]; then
        dialog --msgbox "No reports match your input." 8 40
        return
    fi

    CHOSEN=$(dialog --title "Dormant Reports" \
        --menu "Select a report to view:" 20 70 10 \
        "${OPTIONS[@]}" \
        3>&1 1>&2 2>&3)

    if [ -n "$CHOSEN" ]; then
        dialog --textbox "${FILE_MAP[$CHOSEN]}" 25 80
    fi
}



# -------- Manage Cybersecurity Professionals --------

manage_cybersecurity_professionals() {
    local FILE="/etc/cybersecurity_professionals.conf"
    local TMPFILE="/tmp/cybersec_tmp.$$"
    declare -A professionals

    save_professionals() {
        {
            echo "# Cybersecurity Professionals"
            for name in "${!professionals[@]}"; do
                echo "$name <${professionals[$name]}>"
            done
        } | sudo tee "$FILE" > /dev/null
    }

    # Load entries into associative array
    if [[ -f "$FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            if [[ "$line" == *"<"*">" ]]; then
                name="${line%%<*}"
                name="${name%" "}"  # trim trailing space
                email="${line##*<}"
                email="${email%%>*}"
                professionals["$name"]="$email"
            fi
        done < "$FILE"
    fi

    while true; do
        ACTION=$(dialog --clear --backtitle "Manage Cybersecurity Professionals" \
            --title "Choose Action" \
            --menu "Select an action:" 15 50 6 \
            1 "Search Professionals" \
            2 "Add New Professional" \
            3 "Edit Existing Professional" \
            4 "Delete Professional" \
            5 "Back to Reports Menu" \
            3>&1 1>&2 2>&3)

        [[ -z "$ACTION" || "$ACTION" == "5" ]] && break

        case $ACTION in
            1)  # Search
                dialog --inputbox "Enter search keyword (name or email):" 8 50 2> "$TMPFILE"
                [[ $? -ne 0 ]] && continue
                keyword=$(<"$TMPFILE")
                keyword=$(echo "$keyword" | xargs)
                if [[ -z "$keyword" ]]; then
                    dialog --msgbox "No input entered." 6 40
                    continue
                fi

                OPTIONS=()
                for name in "${!professionals[@]}"; do
                    email="${professionals[$name]}"
                    if [[ "${name,,}" == *"${keyword,,}"* || "${email,,}" == *"${keyword,,}"* ]]; then
                        OPTIONS+=("$name" "$email")
                    fi
                done

                if [ ${#OPTIONS[@]} -eq 0 ]; then
                    dialog --msgbox "No matching professionals found." 6 40
                else
                    dialog --menu "Search results:" 20 60 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3 >/dev/null
                fi
                ;;
            2)  # Add
                dialog --inputbox "Enter full name:" 8 50 2> "$TMPFILE"
                [[ $? -ne 0 ]] && continue
                new_name=$(<"$TMPFILE")
                new_name=$(echo "$new_name" | xargs)

                dialog --inputbox "Enter email address:" 8 50 2> "$TMPFILE"
                [[ $? -ne 0 ]] && continue
                new_email=$(<"$TMPFILE")
                new_email=$(echo "$new_email" | xargs)

                if [[ -z "$new_name" || -z "$new_email" ]]; then
                    dialog --msgbox "Name and email cannot be empty." 6 40
                    continue
                fi

                if [[ -n "${professionals[$new_name]}" ]]; then
                    dialog --yesno "Entry with this name exists. Overwrite?" 7 50
                    [[ $? -ne 0 ]] && continue
                fi

                professionals["$new_name"]="$new_email"
                save_professionals
                dialog --msgbox "User added/updated." 5 30
                ;;
            3)  # Edit
                if [ ${#professionals[@]} -eq 0 ]; then
                    dialog --msgbox "No users to edit." 6 40
                    continue
                fi

                OPTIONS=()
                for name in "${!professionals[@]}"; do
                    OPTIONS+=("$name" "${professionals[$name]}")
                done

                SELECTED=$(dialog --menu "Select user to edit:" 20 60 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
                [[ -z "$SELECTED" ]] && continue

                cur_email="${professionals[$SELECTED]}"

                EDIT_ACTION=$(dialog --menu "Edit $SELECTED <$cur_email>: Select action" 15 50 3 \
                    1 "Update Email" \
                    2 "Rename User" \
                    3 "Cancel" \
                    3>&1 1>&2 2>&3)

                case "$EDIT_ACTION" in
                    1)
                        dialog --inputbox "Enter new email for $SELECTED:" 8 60 "$cur_email" 2> "$TMPFILE"
                        if [[ $? -eq 0 ]]; then
                            new_email=$(<"$TMPFILE")
                            new_email=$(echo "$new_email" | xargs)
                            if [[ -n "$new_email" ]]; then
                                professionals["$SELECTED"]="$new_email"
                                save_professionals
                                dialog --msgbox "User updated." 5 30
                            else
                                dialog --msgbox "Email empty. Update cancelled." 5 30
                            fi
                        fi
                        ;;
                    2)
                        dialog --inputbox "Enter new name for $SELECTED:" 8 50 "$SELECTED" 2> "$TMPFILE"
                        if [[ $? -eq 0 ]]; then
                            new_name=$(<"$TMPFILE")
                            new_name=$(echo "$new_name" | xargs)
                            if [[ -n "$new_name" ]]; then
                                if [[ "$new_name" != "$SELECTED" && -n "${professionals[$new_name]}" ]]; then
                                    dialog --msgbox "Name exists. Rename cancelled." 5 30
                                else
                                    professionals["$new_name"]="${professionals[$SELECTED]}"
                                    unset 'professionals[$SELECTED]'
                                    save_professionals
                                    dialog --msgbox "User updated." 5 30
                                fi
                            else
                                dialog --msgbox "Name empty. Rename cancelled." 5 30
                            fi
                        fi
                        ;;
                    3|*) ;;  # Cancel
                esac
                ;;
            4)  # Delete
                if [ ${#professionals[@]} -eq 0 ]; then
                    dialog --msgbox "No users to delete." 6 40
                    continue
                fi

                OPTIONS=()
                for name in "${!professionals[@]}"; do
                    OPTIONS+=("$name" "${professionals[$name]}")
                done

                DEL_SELECTED=$(dialog --menu "Select user to delete:" 20 60 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
                [[ -z "$DEL_SELECTED" ]] && continue

                dialog --yesno "Are you sure you want to delete $DEL_SELECTED <${professionals[$DEL_SELECTED]}>?" 7 60
                if [[ $? -eq 0 ]]; then
                    unset 'professionals[$DEL_SELECTED]'
                    save_professionals
                    dialog --msgbox "User deleted." 5 30
                fi
                ;;
        esac
    done

    rm -f "$TMPFILE"
}


# -------- Update sysadmin name --------
update_sysadmin_name() {
    local CONFIG="/etc/dormant.conf"
    local TMPFILE="/tmp/sysadmin_tmp.$$"

    # Extract current sysadmin_name value
    local current_name=$(grep -Po '^sysadmin_name=".*?"' "$CONFIG" 2>/dev/null | sed -E 's/sysadmin_name="(.*)"/\1/')

    # Prompt user to update
    dialog --inputbox "Current sysadmin name:\n$([ -z "$current_name" ] && echo '(empty)')" 8 60 "$current_name" 2> "$TMPFILE"
    if [[ $? -ne 0 ]]; then
        rm -f "$TMPFILE"
        return
    fi

    local new_name=$(<"$TMPFILE")
    new_name=$(echo "$new_name" | xargs)  # trim whitespace

    if [[ -z "$new_name" ]]; then
        dialog --yesno "You entered an empty name.\nThis will remove the sysadmin_name entry from the config.\nProceed?" 8 60
        if [[ $? -eq 0 ]]; then
            sudo sed -i '/^sysadmin_name=/d' "$CONFIG"
            dialog --msgbox "sysadmin_name removed from config." 6 40
        else
            dialog --msgbox "No changes made." 6 40
        fi
    else
        if grep -q '^sysadmin_name=' "$CONFIG"; then
            sudo sed -i "s|^sysadmin_name=.*|sysadmin_name=\"$new_name\"|" "$CONFIG"
        else
            echo "sysadmin_name=\"$new_name\"" | sudo tee -a "$CONFIG" > /dev/null
        fi
        dialog --msgbox "sysadmin_name updated to: $new_name" 6 50
    fi

    rm -f "$TMPFILE"
}


# -------- set account expiry --------
set_expiry() {
    # Get all users with UID >= 1000 (normal users)
    mapfile -t all_users < <(awk -F: '($3>=1000)&&($1!="nobody"){print $1}' /etc/passwd)

    if [ ${#all_users[@]} -eq 0 ]; then
        dialog --msgbox "No standard users found." 8 40
        return
    fi

    while true; do
        # Ask for search input
        dialog --inputbox "Enter username to search (leave blank to list all):" 8 60 2> "$TMPFILE"
        if [ $? -ne 0 ]; then
            return
        fi
        search=$(<"$TMPFILE")

        # Filter users based on search input
        if [ -z "$search" ]; then
            filtered_users=("${all_users[@]}")
        else
            filtered_users=()
            for u in "${all_users[@]}"; do
                if [[ "$u" == *"$search"* ]]; then
                    filtered_users+=("$u")
                fi
            done

            if [ ${#filtered_users[@]} -eq 0 ]; then
                dialog --msgbox "No users found matching \"$search\"." 8 40
                continue
            fi
        fi

        # Build options array with username + expiry date
        OPTIONS=()
        for u in "${filtered_users[@]}"; do
            # Get expiry date, fallback to "No expiry"
            expiry=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2- | xargs)
            [[ -z "$expiry" ]] && expiry="No expiry"
            OPTIONS+=("$u" "$expiry")
        done

        # Show menu to pick a user
        selected_user=$(dialog --menu "Select a user to set expiry date:\n(Search: $search)" 20 70 15 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
        if [ -z "$selected_user" ]; then
            return
        fi

        # Input new expiry date
        dialog --inputbox "Enter expiry date for $selected_user (YYYY-MM-DD), or empty to remove expiry:" 8 60 2> "$TMPFILE"
        if [ $? -ne 0 ]; then
            continue
        fi
        expiry_date=$(<"$TMPFILE")

        if [ -z "$expiry_date" ]; then
            # Remove expiry (set to never expire)
            sudo chage -E -1 "$selected_user"
            dialog --msgbox "Expiry removed for user $selected_user." 8 50
        else
            # Validate date format
            if date -d "$expiry_date" &>/dev/null; then
                sudo chage -E "$expiry_date" "$selected_user"
                dialog --msgbox "Expiry date set for $selected_user: $expiry_date" 8 50
            else
                dialog --msgbox "Invalid date format. Please try again." 8 50
            fi
        fi
    done
}

    

# -------- create user --------
create_user() {
    step=1
    newuser=""
    useremail=""
    password=""
    password_confirm=""
    sudo_answer=""

    while true; do
        case $step in
            1)
                dialog --cancel-label "Back to Menu" --ok-label "Next" \
                    --inputbox "Enter new username:" 8 40 2> "$TMPFILE"
                result=$?
                if [[ $result -ne 0 ]]; then return; fi
                newuser=$(<"$TMPFILE")

                if id "$newuser" &>/dev/null; then
                    dialog --msgbox "User '$newuser' already exists." 8 40
                else
                    step=2
                fi
                ;;
            2)
                dialog --cancel-label "Back" --ok-label "Next" \
                    --inputbox "Enter email for $newuser:" 8 60 2> "$TMPFILE"
                result=$?
                if [[ $result -ne 0 ]]; then step=1; continue; fi
                useremail=$(<"$TMPFILE")
                step=3
                ;;
            3)
                dialog --cancel-label "Back" --ok-label "Next" \
                    --insecure --passwordbox "Enter password for $newuser:" 8 40 2> "$TMPFILE"
                result=$?
                if [[ $result -ne 0 ]]; then step=2; continue; fi
                password=$(<"$TMPFILE")
                step=4
                ;;
            4)
                dialog --cancel-label "Back" --ok-label "Next" \
                    --insecure --passwordbox "Confirm password for $newuser:" 8 40 2> "$TMPFILE"
                result=$?
                if [[ $result -ne 0 ]]; then step=3; continue; fi
                password_confirm=$(<"$TMPFILE")

                if [[ "$password" != "$password_confirm" ]]; then
                    dialog --msgbox "Passwords do not match." 8 40
                    step=3
                else
                    step=5
                fi
                ;;
            5)
                dialog --cancel-label "Back" --yes-label "Yes" --no-label "No" \
                    --yesno "Should $newuser have root privileges?" 7 50
                result=$?
                case $result in
                    0) sudo_answer="Yes"; step=6 ;;
                    1) sudo_answer="No"; step=6 ;;
                    255) step=4 ;;
                esac
                ;;
            6)
                homedir="/home/$newuser"
                dialog --yes-label "Confirm" --no-label "Back" \
                    --yesno "Please confirm the user details:\n\nUsername: $newuser\nEmail: $useremail\nHome: $homedir\nRoot Privileges: $sudo_answer\n\nProceed?" 16 60
                result=$?
                if [[ $result -eq 0 ]]; then
                    sudo useradd -m "$newuser" || {
                        dialog --msgbox "Failed to create user." 8 40
                        return
                    }
                    echo "$newuser:$password" | sudo chpasswd

                    if [[ "$sudo_answer" == "Yes" ]]; then
                        sudo usermod -aG sudo "$newuser"
                    fi

                    if ! grep -q "^$newuser=" "$EMAIL_CONF" 2>/dev/null; then
                        echo "$newuser=$useremail" | sudo tee -a "$EMAIL_CONF" > /dev/null
                    else
                        sudo sed -i "s/^$newuser=.*/$newuser=$useremail/" "$EMAIL_CONF"
                    fi

                    dialog --msgbox "User $newuser created successfully.\nEmail saved." 10 50
                    return
                else
                    step=5
                fi
                ;;
        esac
    done
}

# -------- update email (single user) --------
update_email() {
    if [ ! -f "$EMAIL_CONF" ]; then
        dialog --msgbox "Email config file not found at $EMAIL_CONF." 8 50
        return
    fi

    mapfile -t users < <(cut -d= -f1 "$EMAIL_CONF")
    if [ ${#users[@]} -eq 0 ]; then
        dialog --msgbox "No users found in $EMAIL_CONF." 8 50
        return
    fi

    OPTIONS=()
    for u in "${users[@]}"; do
        email=$(grep "^$u=" "$EMAIL_CONF" | cut -d= -f2-)
        OPTIONS+=("$u" "$email")
    done

    selected_user=$(dialog --menu "Select user to update email:" 20 60 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
    if [ -z "$selected_user" ]; then
        return
    fi

    dialog --inputbox "Enter new email for $selected_user:" 8 60 2> "$TMPFILE"
    if [ $? -ne 0 ]; then return; fi
    new_email=$(<"$TMPFILE")

    sudo sed -i "s/^$selected_user=.*/$selected_user=$new_email/" "$EMAIL_CONF"
    dialog --msgbox "Email for $selected_user updated successfully." 8 50
}

# -------- update config --------
update_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Config file not found: $CONFIG_FILE" 8 50
        return
    fi

    source "$CONFIG_FILE"

    CHOICE=$(dialog --menu "Which setting do you want to update?" 20 60 10 \
        1 "User Dormancy (Current: $DORMANT_USERACCOUNT_DURATION days)" \
        2 "Service Dormancy (Current: $DORMANT_SERVICEACCOUNT_DURATION days)" \
        3 "Password Expiry (Current: $DORMANT_PASSWORD_EXPIRY_DURATION days)" \
        4 "Cron Schedule (Current: $DORMANT_CRON_SCHEDULE)" \
        5 "Back" \
        3>&1 1>&2 2>&3)

    case $CHOICE in
        1)
            NEW=$(dialog --inputbox "Enter new dormant user account duration (days):" 8 50 "$DORMANT_USERACCOUNT_DURATION" 2>&1 >/dev/tty)
            if [[ -n "$NEW" && "$NEW" =~ ^[0-9]+$ ]]; then
                sudo sed -i "s/^DORMANT_USERACCOUNT_DURATION=.*/DORMANT_USERACCOUNT_DURATION=$NEW/" "$CONFIG_FILE"
                dialog --msgbox "Updated user dormancy to $NEW days." 6 50
            else
                dialog --msgbox "Invalid input. Update cancelled." 6 50
            fi
            ;;
        2)
            NEW=$(dialog --inputbox "Enter new dormant service account duration (days):" 8 50 "$DORMANT_SERVICEACCOUNT_DURATION" 2>&1 >/dev/tty)
            if [[ -n "$NEW" && "$NEW" =~ ^[0-9]+$ ]]; then
                sudo sed -i "s/^DORMANT_SERVICEACCOUNT_DURATION=.*/DORMANT_SERVICEACCOUNT_DURATION=$NEW/" "$CONFIG_FILE"
                dialog --msgbox "Updated service dormancy to $NEW days." 6 50
            else
                dialog --msgbox "Invalid input. Update cancelled." 6 50
            fi
            ;;
        3)
            NEW=$(dialog --inputbox "Enter new password expiry duration (days):" 8 50 "$DORMANT_PASSWORD_EXPIRY_DURATION" 2>&1 >/dev/tty)
            if [[ -n "$NEW" && "$NEW" =~ ^[0-9]+$ ]]; then
                sudo sed -i "s/^DORMANT_PASSWORD_EXPIRY_DURATION=.*/DORMANT_PASSWORD_EXPIRY_DURATION=$NEW/" "$CONFIG_FILE"
                dialog --msgbox "Updated password expiry to $NEW days." 6 50
            else
                dialog --msgbox "Invalid input. Update cancelled." 6 50
            fi
            ;;
        4)
            # Cron schedule submenu
            CRON_CHOICE=$(dialog --menu "Update Cron Schedule - Choose method:" 15 50 3 \
                1 "Custom cron schedule (manual input)" \
                2 "Every day at specific time" \
                3 "Cancel" \
                3>&1 1>&2 2>&3)

            case $CRON_CHOICE in
                1)
                    NEW=$(dialog --inputbox "Enter custom cron schedule (e.g. */5 * * * *):" 8 60 "$DORMANT_CRON_SCHEDULE" 2>&1 >/dev/tty)
                    ;;
                2)
                    NEW_HOUR=$(dialog --inputbox "Enter hour (0-23):" 8 30 "0" 2>&1 >/dev/tty)
                    if ! [[ "$NEW_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
                        dialog --msgbox "Invalid hour input." 6 40
                        return
                    fi

                    NEW_MIN=$(dialog --inputbox "Enter minute (0-59):" 8 30 "0" 2>&1 >/dev/tty)
                    if ! [[ "$NEW_MIN" =~ ^([0-9]|[1-5][0-9])$ ]]; then
                        dialog --msgbox "Invalid minute input." 6 40
                        return
                    fi

                    NEW="$NEW_MIN $NEW_HOUR * * *"
                    ;;
                *)
                    return
                    ;;
            esac

            if [[ -z "$NEW" ]]; then
                dialog --msgbox "No schedule provided, update cancelled." 6 40
                return
            fi

            # Update config file
            sudo sed -i "s|^DORMANT_CRON_SCHEDULE=.*|DORMANT_CRON_SCHEDULE=\"$NEW\"|" "$CONFIG_FILE"

            # Update crontab: remove old entry for TARGET_SCRIPT and add new one
            (crontab -l 2>/dev/null | grep -v "$TARGET_SCRIPT" ; echo "$NEW bash $TARGET_SCRIPT") | crontab -

            dialog --msgbox "Crontab updated with schedule:\n$NEW" 6 50
            ;;
        5)
            return
            ;;
        *)
            ;;
    esac

    # Reload config to apply changes
    source "$CONFIG_FILE"
}

# -------- edit existing user --------
edit_existing_user() {
    declare -A user_emails
    if [ -f "$EMAIL_CONF" ]; then
        while IFS='=' read -r u e; do
            user_emails["$u"]="$e"
        done < "$EMAIL_CONF"
    fi

    # Define log file path
    LOGFILE="/var/log/user_edit.log"
    TMPFILE="/tmp/user_edit_tmp.$$"

    while true; do
        mapfile -t all_users < <(awk -F: '($3>=1000)&&($1!="nobody"){print $1}' /etc/passwd)

        if [ ${#all_users[@]} -eq 0 ]; then
            dialog --msgbox "No standard users found." 8 40
            return
        fi

        search=$(dialog --inputbox "Enter username to search (leave blank to list all):" 8 60 2>&1 >/dev/tty)
        if [ $? -ne 0 ]; then return; fi

        if [ -z "$search" ]; then
            filtered_users=("${all_users[@]}")
        else
            filtered_users=()
            for u in "${all_users[@]}"; do
                if [[ "$u" == *"$search"* ]]; then
                    filtered_users+=("$u")
                fi
            done
            if [ ${#filtered_users[@]} -eq 0 ]; then
                dialog --msgbox "No users found matching \"$search\"." 8 40
                continue
            fi
        fi

        OPTIONS=()
        for u in "${filtered_users[@]}"; do
            email="${user_emails[$u]}"
            OPTIONS+=("$u" "${email:-No email}")
        done

        selected_user=$(dialog --menu "Select a user to edit:" 20 70 15 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
        if [ -z "$selected_user" ]; then
            return
        fi

        uid=$(id -u "$selected_user")
        gid=$(id -g "$selected_user")
        groups=$(id -Gn "$selected_user")
        homedir=$(getent passwd "$selected_user" | cut -d: -f6)
        email="${user_emails[$selected_user]:-No email}"
        has_sudo=$(echo "$groups" | grep -qw "sudo" && echo "Yes" || echo "No")

        # Check if user is locked (deactivated)
        passwd_status=$(sudo passwd -S "$selected_user" 2>/dev/null)
        if echo "$passwd_status" | grep -q " L "; then
            active_status="Deactivated (Locked)"
            is_deactivated=true
        else
            active_status="Activated"
            is_deactivated=false
        fi

        dialog --msgbox "User Summary for $selected_user:\n\nUsername: $selected_user\nUID: $uid\nGID: $gid\nHome: $homedir\nEmail: $email\nSudo: $has_sudo\nStatus: $active_status" 14 60

        while true; do
            EDIT_CHOICE=$(dialog --menu "Edit User: $selected_user\nChoose action:" 18 60 12 \
                1 "Reset Password" \
                2 "Update Email" \
                3 "Create Home Directory if Missing" \
                4 "Modify Root Privileges" \
                5 "Remove User Account" \
                6 "Activate / Deactivate User" \
                7 "Back to User Search" \
                3>&1 1>&2 2>&3)

            case $EDIT_CHOICE in
                1)
                    dialog --insecure --passwordbox "Enter new password for $selected_user:" 8 40 2> "$TMPFILE"
                    if [ $? -eq 0 ]; then
                        newpass=$(<"$TMPFILE")
                        echo "$selected_user:$newpass" | sudo chpasswd
                        dialog --msgbox "Password reset for $selected_user." 8 40
                    fi
                    ;;
                2)
                    dialog --inputbox "Enter new email for $selected_user:" 8 60 2> "$TMPFILE"
                    if [ $? -eq 0 ]; then
                        new_email=$(<"$TMPFILE")
                        if grep -q "^$selected_user=" "$EMAIL_CONF"; then
                            sudo sed -i "s/^$selected_user=.*/$selected_user=$new_email/" "$EMAIL_CONF"
                        else
                            echo "$selected_user=$new_email" | sudo tee -a "$EMAIL_CONF" > /dev/null
                        fi
                        dialog --msgbox "Email updated for $selected_user." 8 50
                    fi
                    ;;
                3)
                    if [ ! -d "$homedir" ]; then
                        sudo mkdir -p "$homedir"
                        sudo chown "$selected_user":"$selected_user" "$homedir"
                        dialog --msgbox "Home directory created for $selected_user." 8 50
                    else
                        dialog --msgbox "Home directory already exists." 8 50
                    fi
                    ;;
                4)
                    if [ "$has_sudo" = "Yes" ]; then
                        dialog --yesno "Remove root privileges from $selected_user?" 7 50
                        if [ $? -eq 0 ]; then
                            sudo deluser "$selected_user" sudo
                            dialog --msgbox "Root privileges removed." 8 40
                        fi
                    else
                        dialog --yesno "Grant root privileges to $selected_user?" 7 50
                        if [ $? -eq 0 ]; then
                            sudo usermod -aG sudo "$selected_user"
                            dialog --msgbox "Root privileges granted." 8 40
                        fi
                    fi
                    ;;
                5)
                    dialog --yesno "Are you sure you want to remove user $selected_user? This cannot be undone." 8 50
                    if [ $? -eq 0 ]; then
                        sudo userdel -r "$selected_user"
                        sudo sed -i "/^$selected_user=/d" "$EMAIL_CONF"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') User $selected_user removed" | sudo tee -a "$LOGFILE" > /dev/null
                        dialog --msgbox "User $selected_user removed." 8 50
                        break
                    fi
                    ;;
                6)
                    if [ "$is_deactivated" = true ]; then
                        dialog --yesno "User $selected_user is currently deactivated.\nDo you want to reactivate this user?" 8 60
                        if [ $? -eq 0 ]; then
                            sudo passwd -u "$selected_user"
                            echo "$(date '+%Y-%m-%d %H:%M:%S') User $selected_user reactivated" | sudo tee -a "$LOGFILE" > /dev/null
                            dialog --msgbox "$selected_user has been reactivated." 8 40
                            # Ask if want to reset password on reactivation
                            dialog --yesno "Do you want to reset the password for $selected_user now?" 7 50
                            if [ $? -eq 0 ]; then
                                dialog --insecure --passwordbox "Enter new password for $selected_user:" 8 40 2> "$TMPFILE"
                                if [ $? -eq 0 ]; then
                                    newpass=$(<"$TMPFILE")
                                    echo "$selected_user:$newpass" | sudo chpasswd
                                    dialog --msgbox "Password reset for $selected_user." 8 40
                                fi
                            fi
                        fi
                    else
                        dialog --yesno "User $selected_user is currently active.\nDo you want to deactivate this user?" 8 60
                        if [ $? -eq 0 ]; then
                            sudo passwd -l "$selected_user"
                            echo "$(date '+%Y-%m-%d %H:%M:%S') User $selected_user deactivated" | sudo tee -a "$LOGFILE" > /dev/null
                            dialog --msgbox "$selected_user has been deactivated." 8 40
                            # No password prompt on deactivate
                        fi
                    fi
                    # Update status after change
                    passwd_status=$(sudo passwd -S "$selected_user" 2>/dev/null)
                    if echo "$passwd_status" | grep -q " L "; then
                        active_status="Deactivated (Locked)"
                        is_deactivated=true
                    else
                        active_status="Activated"
                        is_deactivated=false
                    fi
                    ;;
                7) break ;;
                *) break ;;
            esac
        done
    done
}



# -------- Extract current server_url from script --------
get_current_server_url() {
    grep -Po '(?<=local server_url=")[^"]+' "$TARGET_SCRIPT"
}

# -------- Update server URL in script (reuse existing function) --------
update_server_url_ui() {
    current_url=$(get_current_server_url)
    dialog --inputbox "Current ngrok URL:\n$current_url\n\nEnter new ngrok URL:" 10 70 "$current_url" 2> "$TMPFILE"
    new_url=$(<"$TMPFILE")
    if [[ -z "$new_url" ]]; then
        dialog --msgbox "URL cannot be empty." 6 40
        return
    fi

    # Show confirmation
    dialog --yesno "Change ngrok URL from:\n$current_url\nto\n$new_url?" 10 60
    if [ $? -ne 0 ]; then
        dialog --msgbox "Update cancelled." 6 40
        return
    fi

    # Update script
    sudo sed -i -r "s|^\s*local server_url=.*|    local server_url=\"$new_url\"  # updated|" "$TARGET_SCRIPT"

    updated_line=$(grep -P '^\s*local server_url=' "$TARGET_SCRIPT")
    dialog --msgbox "Server URL updated successfully.\n\nUpdated line:\n$updated_line" 10 70
}
  


# -------- generate new ngrok URL and update --------
generate_new_ngrok_url() {
    # Kill existing ngrok processes to avoid conflict
    pkill ngrok 2>/dev/null

    # Open new terminal and run ngrok
    gnome-terminal -- bash -c "ngrok http 8080; exec bash" &

    # Wait for ngrok to initialize
    sleep 5

    # Fetch forwarding URL from ngrok API
    forwarding_url=$(curl --silent http://127.0.0.1:4040/api/tunnels | \
        grep -Po '"public_url":"https://[^"]+' | head -1 | cut -d':' -f2- | tr -d '"')

    if [[ -z "$forwarding_url" ]]; then
        dialog --msgbox "Failed to get ngrok URL. Make sure ngrok is running." 6 50
        return 1
    fi

    # Update your dormant.sh or config with the new URL
    sudo sed -i -r "s|^\s*local server_url=.*|    local server_url=\"$forwarding_url\"  # updated URL |" "$TARGET_SCRIPT"

    dialog --msgbox "New ngrok URL generated:\n$forwarding_url\n\nNgrok running in new terminal." 10 70
}


   
# -------- Update Gmail Cedentials UI (Combined Email & App Password) --------
update_gmail_credentials_ui() {
    local GMAIL_CONF="/etc/gmail.conf"
    local TMPFILE=$(mktemp)

    # Load current values or set defaults
    local current_from=""
    local current_login=""
    local current_password=""

    if [[ -f "$GMAIL_CONF" ]]; then
        source "$GMAIL_CONF"
        current_from=${from_email:-""}
        current_login=${login_email:-""}
        current_password=${app_password:-""}
    fi

    # Show current config summary
    dialog --msgbox "Current Gmail Credentials:\n\nFrom Email: $current_from\nLogin Email: $current_login\nApp Password: $current_password" 12 60

    # Update From Email
    dialog --inputbox "Enter From Email (-f):" 8 60 "$current_from" 2> "$TMPFILE"
    local new_from=$(<"$TMPFILE")
    [[ -z "$new_from" ]] && { dialog --msgbox "From Email cannot be empty. Update cancelled." 6 50; rm -f "$TMPFILE"; return 1; }

    # Update Login Email
    dialog --inputbox "Enter Login Email (-xu):" 8 60 "$current_login" 2> "$TMPFILE"
    local new_login=$(<"$TMPFILE")
    [[ -z "$new_login" ]] && { dialog --msgbox "Login Email cannot be empty. Update cancelled." 6 50; rm -f "$TMPFILE"; return 1; }

    # Update App Password (plain input, no masking)
    dialog --inputbox "Enter App Password (-xp):" 8 60 "$current_password" 2> "$TMPFILE"
    local new_password=$(<"$TMPFILE")
    [[ -z "$new_password" ]] && { dialog --msgbox "App Password cannot be empty. Update cancelled." 6 50; rm -f "$TMPFILE"; return 1; }

    # Confirm updates with visible password
    dialog --yesno "Confirm update Gmail credentials?\n\nFrom Email: $new_from\nLogin Email: $new_login\nApp Password: $new_password" 10 60
    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Update cancelled." 6 40
        rm -f "$TMPFILE"
        return 1
    fi

    # Write new config securely with lowercase variable names
    sudo bash -c "cat > $GMAIL_CONF" <<EOL
# Gmail SMTP credentials for sending alerts
from_email=$new_from
login_email=$new_login
app_password=$new_password
EOL

    sudo chmod 600 "$GMAIL_CONF"
    sudo chown root:root "$GMAIL_CONF"

    dialog --msgbox "Gmail credentials updated successfully in $GMAIL_CONF." 6 50
    rm -f "$TMPFILE"
    return 0
}


# ------------- Start script -------------
main_menu
clear
rm -f "$TMPFILE"
exit 0
