#!/usr/bin/env python3
import os
import struct
import pwd
import time
import random

LASTLOG_PATH = "/var/log/lastlog"

# Get all system users you want to modify
for i in range(1, 51):
    username = f"user{i:02d}"
    
    try:
        pw = pwd.getpwnam(username)
        uid = pw.pw_uid
    except KeyError:
        print(f"User {username} does not exist, skipping.")
        continue

    # Apply your login rules
    if i % 3 == 0:
        days_ago = random.randint(71, 100)
    elif i % 5 == 0:
        days_ago = random.randint(31, 69)
    elif i % 2 == 0:
        days_ago = random.randint(51, 70)
    else:
        days_ago = random.randint(1, 29)

    login_time = int(time.time() - days_ago * 86400)
    line = b"pts/0".ljust(32, b'\x00')
    host = b"localhost".ljust(256, b'\x00')

    # Structure: time (I), line (32s), host (256s)
    data = struct.pack("I32s256s", login_time, line, host)

    offset = uid * struct.calcsize("I32s256s")

    with open(LASTLOG_PATH, "r+b") as f:
        f.seek(offset)
        f.write(data)

    print(f"Updated {username} (UID {uid}) lastlog to {days_ago} days ago.")
