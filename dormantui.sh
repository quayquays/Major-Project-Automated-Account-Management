#admin 
#!/bin/bash

REPORT_DIR="/dormant_reports"
TMPFILE=$(mktemp)

main_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "Dormant User Management UI" \
            --title "Main Menu" \
            --menu "Choose an option:" 15 50 5 \
            1 "View Dormant Reports" \
            2 "Set Account Expiry" \
            3 "Exit" \
            3>&1 1>&2 2>&3)

        case $CHOICE in
            1) view_reports ;;
            2) set_expiry ;;
            3) clear; break ;;
        esac
    done
}

view_reports() {
    mapfile -t files < <(ls -t "$REPORT_DIR"/dormant_report_*.txt 2>/dev/null)
    if [ ${#files[@]} -eq 0 ]; then
        dialog --msgbox "No reports found in $REPORT_DIR." 10 40
        return
    fi

    OPTIONS=()
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        OPTIONS+=("$file" "$filename")
    done

    FILE=$(dialog --title "Dormant Reports" \
        --menu "Select a report to view:" 20 70 10 \
        "${OPTIONS[@]}" \
        3>&1 1>&2 2>&3)

    if [ -n "$FILE" ]; then
        dialog --textbox "$FILE" 25 80
    fi
}

set_expiry() {
    dialog --inputbox "Enter username:" 8 40 2> "$TMPFILE"
    username=$(<"$TMPFILE")

    if ! id "$username" &>/dev/null; then
        dialog --msgbox "User '$username' not found." 8 40
        return
    fi

    dialog --inputbox "Enter expiry date (YYYY-MM-DD):" 8 40 2> "$TMPFILE"
    expiry_date=$(<"$TMPFILE")

    if date -d "$expiry_date" &>/dev/null; then
        sudo chage -E "$expiry_date" "$username"
        dialog --msgbox "Expiry date set for $username: $expiry_date" 8 50
    else
        dialog --msgbox "Invalid date format." 8 40
    fi
}

trap "rm -f $TMPFILE" EXIT
main_menu
