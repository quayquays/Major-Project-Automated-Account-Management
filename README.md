# Dormant User Management System

A bash-based system to monitor dormant user accounts, manage password expiry, and easily create or update user accounts via a text-based dialog UI.

---


---

## Usage Steps

### 1. Create a directory, name it whatever you want. Just make sure it's in root. [ e.g /dormant , /Dormant etc..]. Make sure you put the following files in that directory. [✨]

- dormant2.0.sh
- dormantui.sh
- server.py
- setup.sh

### 2. Run setup.sh

When running the file, you might face some errors while installing the dependencies. Which is normal, so do not fret 💖. 
Usually, from the output you can see on how to fix those issues.
After fixing it, run the setup.sh again and make sure everything is installed.





### 3. Check if everything is installed properly.

- Check if server.py runs in the background

  
sudo systemctl daemon-reload


sudo systemctl restart serverpy.service


sudo systemctl status serverpy.service

If it gives errors try to kill the proccess:

sudo lsof -i :8080

sudo kill -9 <id>


 - Check for the log files
   
 cat /var/log/dormant.log
 
 cat /var/log/server.log

  - Check if dormant.sh is automatically installed in the cronjob.

    crontab -l

### 4. Set up Ngrock account.

Thanks Yu Xuan for the detailed steps, I just copy paste 🥹🥰

1. Go to ngrok's website and create an account
2. Go to "Setup & Installation" -> "Linux" -> "Apt" -> Follow the steps given (stop before "Deploy your app online")
3. ngrok http 8080
4. A ngrok session will be shown
5. Copy the link at the "Forwarding" section (eg. "https://cc87d8decd23.ngrok-free.app")
6. Edit dormant.sh accordingly with updated script 
7. In dormant.sh, change your server-url to the forwarding link

Another way to do is:

#### Through the UI.
Just make sure you do steps one and two before you do this.

1) Run dormantui.sh
2) Go to system configurations --> Generate ngrock URL
- This will open a new terminal [ DONT CLOSE IT ]
- And it will automatically update it in the script for you.

But if you did till steps 5 you can also manually update it, through the UI.

1) Go to system and configuration --> Manual Update URL [ I think i forgot ]


### 4. Run dormantui.sh.
There are several things you can do in this UI. 


- Set up your gmail credentials [ For the SMTP ] ⚠️✨
- Set up your ngrock
- I will continue to write more tommorow



## If you want to check for the python service.

1) Disable

sudo systemctl stop serverpy.service

sudo systemctl disable serverpy.service


3) Update your server.py 

4) Run ./setup.sh

    

