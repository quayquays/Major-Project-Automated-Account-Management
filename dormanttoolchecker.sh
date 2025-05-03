#!/bin/bash

#load the configuration file to get the durations
source /etc/dormant.conf

#double check if the config file has the required parameters
if [ -z "$DORMANT_USERACCOUNT_DURATION" ] || [ -z "$DORMANT_SERVICEACCOUNT_DURATION" ]; then
    echo "Error: Config file missing required parameters."
    exit 1
fi

#duration output check
echo "Duration of User account: $DORMANT_USERACCOUNT_DURATION days"
echo "Duration of Service account: $DORMANT_SERVICEACCOUNT_DURATION days"

#extract the list of user accounts
check_user_account() {
    #extract the list of usernames with UID >= 1000 in a variable (to store it)
    user_account=$(grep '^[^:]*:[^:]*:[1-9][0-9]\{3,\}:' /etc/passwd | cut -d: -f1)
} 

#detect and see if user accounts are dormant
detect_dormant_user() {
    #store the list of detected users 
    dormant_detected_user=() 

    for user in $user_account; do
        #extract the login date for the user
        lastlogin=$(lastlog -u "$user" | awk 'NR==2')

        #if the login date  not found or invalid skip this user
        if [[ -z "$lastlogin" ]] || [[ "$lastlogin" == *"Never logged in"* ]]; then
            #echo "No valid last login date for user $user."
            continue
        fi

        #extract date
        last_login_date=$(echo "$lastlogin" | awk '{print $4, $5, $6}')
        
        #see if the login date is valid
        if [[ -n "$last_login_date" ]]; then
            #converting login date
            if last_login_ts=$(date -d "$last_login_date" +%s 2>/dev/null); then
                today_date=$(date +%Y-%m-%d)
                today_ts=$(date -d "$today_date" +%s)
                difference=$(( (today_ts - last_login_ts) / 86400 ))  # Convert seconds to days
                
                echo "User $user last logged in on: $last_login_date ($difference days ago)"
                
                #compare the differences 
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

   #after looping it print the dormant users
    if [[ ${#dormant_detected_user[@]} -gt 0 ]]; then
        echo "Dormant users detected: ${dormant_detected_user[*]}"
    else
        echo "No dormant users detected."
    fi
}

#function to generate reports for the admin to see what is missing 
generate_report() {
    REPORT_DIR="/dormant_reports"
    [ ! -d "$REPORT_DIR" ] && mkdir -p "$REPORT_DIR"

    timestamp=$(date "+%d %b %Y %I:%M %p")

    report_file="$REPORT_DIR/dormant_report_$timestamp.txt"

    {
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users Report 📜- $timestamp "
        echo "---------------------------------------------------------------------------"
        echo "Dormant Users 👥 "
        echo "---------------------------------------------------------------------------"
        #call the function from detect_dormant_users function 
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
        echo "Email Pending 📩"
        echo
        echo "---------------------------------------------------------------------------"
        echo "Inactive (Deactivated Accounts)"
        echo "---------------------------------------------------------------------------"
    } >> "$report_file"

    echo "Report generated at: $report_file"
}

#call function to extract users
check_user_account

#call the function to check dormant users
detect_dormant_user

#call the generate report 
generate_report
