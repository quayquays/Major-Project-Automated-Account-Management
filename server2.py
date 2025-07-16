#the token feature is not working for uuid and json it is downloaded in python3 it is the code's error.

from flask import Flask, request, render_template_string, redirect, url_for
import os
import datetime
import subprocess
import uuid
import json

app = Flask(__name__)

OPT_IN_FILE = "/etc/dormant_opt_in.conf"
DEACTIVATED_LOG = "/var/log/dormant/deactivated_users.log"
TOKEN_STORE_FILE = "/var/lib/dormant_tokens.json"

# Ensure token store dir exists
os.makedirs(os.path.dirname(TOKEN_STORE_FILE), exist_ok=True)

RESET_FORM_HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>Reset Password</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; background: #f9f9f9; }
        form { background: #fff; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); width: 400px; margin: auto; }
        h2 { color: #333; }
        label { display: block; margin-top: 15px; }
        input[type="password"], input[type="submit"] {
            width: 100%; padding: 10px; margin-top: 5px; border-radius: 5px; border: 1px solid #ccc;
        }
        input[type="submit"] {
            background-color: #007bff; color: white; border: none; margin-top: 20px;
        }
        input[type="submit"]:hover {
            background-color: #0056b3;
        }
    </style>
</head>
<body>
    <form method="POST">
        <h2>🔐 Reset Password for {{ user }}</h2>
        <input type="hidden" name="token" value="{{ token }}">
        <label>New Password:</label>
        <input type="password" name="password" required>
        <label>Confirm Password:</label>
        <input type="password" name="confirm_password" required>
        <input type="submit" value="Update Password">
    </form>
</body>
</html>
'''

def load_tokens():
    if os.path.exists(TOKEN_STORE_FILE):
        with open(TOKEN_STORE_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_tokens(tokens):
    with open(TOKEN_STORE_FILE, 'w') as f:
        json.dump(tokens, f)

def generate_token(user):
    token = str(uuid.uuid4())
    tokens = load_tokens()
    tokens[token] = user
    save_tokens(tokens)
    return token

@app.route('/confirm')
def confirm():
    token = request.args.get('token')
    tokens = load_tokens()
    user = tokens.pop(token, None)

    if not user:
        return "❌ Invalid or already used token.", 400

    save_tokens(tokens)  # remove token after use

    now = datetime.datetime.now().strftime("%Y-%m-%d")
    os.makedirs(os.path.dirname(OPT_IN_FILE), exist_ok=True)

    # Remove existing opt-ins
    lines = []
    if os.path.exists(OPT_IN_FILE):
        with open(OPT_IN_FILE, 'r') as f:
            lines = f.readlines()

    with open(OPT_IN_FILE, 'w') as f:
        for line in lines:
            if not line.startswith(f"{user}="):
                f.write(line)
        f.write(f"{user}={now}\n")

    # Generate a new one-time token for password reset
    reset_token = generate_token(user)
    return redirect(url_for('reset_password', token=reset_token))

@app.route('/reset_password', methods=['GET', 'POST'])
def reset_password():
    token = request.args.get('token') or request.form.get('token')
    tokens = load_tokens()
    user = tokens.get(token)

    if not user:
        return "❌ Invalid or expired token.", 400

    if request.method == 'GET':
        return render_template_string(RESET_FORM_HTML, user=user, token=token)

    password = request.form.get('password')
    confirm = request.form.get('confirm_password')

    if not password or not confirm:
        return "⚠️ Please fill out both fields.", 400
    if password != confirm:
        return "❌ Passwords do not match.", 400

    try:
        subprocess.run(['bash', '-c', f'echo "{user}:{password}" | chpasswd'], check=True)
        today_str = datetime.datetime.now().strftime("%Y-%m-%d")
        subprocess.run(['chage', '-d', today_str, user], check=True)

        # Remove token after successful password reset
        tokens.pop(token, None)
        save_tokens(tokens)

        return f"✅ Password updated successfully for {user}. You may now log in."
    except Exception as e:
        return f"⚠️ Error updating password: {e}", 500

@app.route('/deactivate/<username>', methods=['GET'])
def deactivate_account(username):
    try:
        subprocess.run(['usermod', '-L', username], check=True)
        subprocess.run(['usermod', '-s', '/sbin/nologin', username], check=True)

        os.makedirs(os.path.dirname(DEACTIVATED_LOG), exist_ok=True)
        with open(DEACTIVATED_LOG, 'a') as f:
            f.write(f"{username} deactivated via email at {datetime.datetime.now()}\n")

        return f"❌ Your account '{username}' has been deactivated."
    except Exception as e:
        return f"⚠️ Failed to deactivate account '{username}': {e}"

@app.route('/')
def index():
    return "🛡️ Dormant Account Manager Running"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
