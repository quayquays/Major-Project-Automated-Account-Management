# Dormant User Management System

A bash-based system to monitor dormant user accounts, manage password expiry, and easily create or update user accounts via a text-based dialog UI.

---


---

## Usage Steps

### 1. Run `setup.sh`

This script will:

- Create the config file `/etc/dormant.conf` if it does not exist  
- Move `dormant.sh` to `/usr/local/bin/` and make it executable  
- Install a cron job to run `dormant.sh` daily at the configured time (default 8:02 PM)

**Run it with:**

chmod +x setup.sh

./setup.sh


### 2. Run `dormantui.sh`

This launches the interactive user interface for managing dormant users and accounts.

Features include:

- Viewing generated dormant user reports  
- Setting expiry dates for accounts  
- Creating new user accounts with email and password setup  
- Updating user emails  
- Navigating back and forth in dialogs without losing progress
- update existing user email, sudo privelages etc
- update cronjob time, password expiry days, user expiry days etc 

IMPORTANT THING TO TAKE NOTE : MAKE SURE YOU ARE IN ROOT OR A USER WITH SUDO PRIV TO RUN THIS SCRIPT

**Run it with:**

chmod +x dormantui.sh


./dormantui.sh
