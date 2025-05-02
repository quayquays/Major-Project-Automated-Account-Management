#!/bin/bash

# Change this default password if you want
DEFAULT_PASSWORD="Password123"

# Loop to create 50 users
for i in $(seq -w 1 50); do
    USERNAME="user${i}"
    
    # Check if user already exists
    if id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME already exists. Skipping..."
    else
        # Create the user with a home directory
        useradd -m "$USERNAME"

        # Set the password
        echo "$USERNAME:$DEFAULT_PASSWORD" | chpasswd

        # Optionally force user to change password at first login
        chage -d 0 "$USERNAME"

        echo "User $USERNAME created."
    fi
done
