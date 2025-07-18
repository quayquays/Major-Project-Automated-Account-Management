from flask import Flask, request, render_template_string, redirect, url_for, abort
import os
import datetime
import subprocess
import hmac
import hashlib
import base64

app = Flask(__name__)

OPT_IN_FILE = "/etc/dormant_opt_in.conf"
OPT_OUT_FILE = "/etc/dormant_opt_out.conf"   # To track users who clicked No
DEACTIVATED_LOG = "/var/log/dormant/deactivated_users.log"
PASSWORD_RESET_LOG = "/var/log/dormant/password_reset.log"

# Secret key for HMAC token generation — store securely, e.g., env var
SECRET_KEY = b'your-very-secure-secret-key'

RESET_FORM_HTML = '''
<h2>🔐 Reset Password for {{ user }}</h2>
<form method="POST">
  <input type="hidden" name="user" value="{{ user }}">
  <input type="hidden" name="token" value="{{ token }}">
  <label>New Password:</label><br>
  <input type="password" name="password"><br><br>
  <label>Confirm Password:</label><br>
  <input type="password" name="confirm_password"><br><br>
  <input type="submit" value="Update Password">
</form>
'''

MESSAGE_HTML = '''
<h3>{{ message }}</h3>
'''

def generate_token(user):
    timestamp = datetime.datetime.utcnow().strftime("%Y%m%d%H%M")
    msg = f"{user}:{timestamp}".encode()
    digest = hmac.new(SECRET_KEY, msg, hashlib.sha256).digest()
    token = base64.urlsafe_b64encode(digest).decode()
    return f"{token}:{timestamp}"

def verify_token(user, token):
    try:
        token_value, timestamp = token.split(":")
        # Check token expiry: valid for 1 day
        token_time = datetime.datetime.strptime(timestamp, "%Y%m%d%H%M")
        now = datetime.datetime.utcnow()
        if abs((now - token_time).total_seconds()) > 86400:
            return False
        # Recompute HMAC and compare
        msg = f"{user}:{timestamp}".encode()
        expected_digest = hmac.new(SECRET_KEY, msg, hashlib.sha256).digest()
        expected_token = base64.urlsafe_b64encode(expected_digest).decode()
        return hmac.compare_digest(token_value, expected_token)
    except Exception:
        return False

def update_opt_in(user):
    now = datetime.datetime.now().strftime("%Y-%m-%d")
    lines = []
    if os.path.exists(OPT_IN_FILE):
        with open(OPT_IN_FILE, 'r') as f:
            lines = f.readlines()
    with open(OPT_IN_FILE, 'w') as f:
        for line in lines:
            if not line.startswith(f"{user}="):
                f.write(line)
        f.write(f"{user}={now}\n")
    # Also remove opt-out flag if any
    if os.path.exists(OPT_OUT_FILE):
        with open(OPT_OUT_FILE, 'r') as f:
            lines = f.readlines()
        with open(OPT_OUT_FILE, 'w') as f:
            for line in lines:
                if not line.startswith(f"{user}="):
                    f.write(line)

def update_opt_out(user):
    now = datetime.datetime.now().strftime("%Y-%m-%d")
    lines = []
    if os.path.exists(OPT_OUT_FILE):
        with open(OPT_OUT_FILE, 'r') as f:
            lines = f.readlines()
    with open(OPT_OUT_FILE, 'w') as f:
        for line in lines:
            if not line.startswith(f"{user}="):
                f.write(line)
        f.write(f"{user}={now}\n")
    # Also remove opt-in flag if any
    if os.path.exists(OPT_IN_FILE):
        with open(OPT_IN_FILE, 'r') as f:
            lines = f.readlines()
        with open(OPT_IN_FILE, 'w') as f:
            for line in lines:
                if not line.startswith(f"{user}="):
                    f.write(line)

def has_password_been_reset(user):
    if not os.path.exists(PASSWORD_RESET_LOG):
        return False
    with open(PASSWORD_RESET_LOG, 'r') as f:
        for line in f:
            if line.startswith(user):
                return True
    return False

def log_password_reset(user):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(PASSWORD_RESET_LOG, 'a') as f:
        f.write(f"{user} reset password at {now}\n")

@app.route('/confirm')
def confirm():
    user = request.args.get('user')
    token = request.args.get('token')
    response = request.args.get('response')

    if not user or not token or response != "yes":
        return "⚠️ Missing parameters or invalid response.", 400

    if not verify_token(user, token):
        return "⚠️ Invalid or expired token.", 403

    update_opt_in(user)

    # Show message and redirect to password reset
    message = f"✅ Your account '{user}' will be reactivated. Please reset your password."
    reset_url = url_for('reset_password', user=user, token=token)
    return f'''
    <h3>{message}</h3>
    <p><a href="{reset_url}">Click here to reset your password</a></p>
    '''

@app.route('/reset_password', methods=['GET', 'POST'])
def reset_password():
    user = request.args.get('user') or request.form.get('user')
    token = request.args.get('token') or request.form.get('token')

    if not user or not token:
        return "⚠️ Missing user or token.", 400

    if not verify_token(user, token):
        return "⚠️ Invalid or expired token.", 403

    if has_password_been_reset(user):
        return render_template_string(MESSAGE_HTML, message=f"ℹ️ Password for '{user}' has already been reset. This form cannot be used again.")

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

        log_password_reset(user)

        return f"✅ Password updated successfully for {user}. You may now log in."
    except Exception as e:
        return f"⚠️ Error updating password: {e}", 500

@app.route('/deactivate/<username>')
def deactivate_account(username):
    token = request.args.get('token')

    if not username or not token:
        return "⚠️ Missing username or token.", 400
    if not verify_token(username, token):
        return "⚠️ Invalid or expired token.", 403

    try:
        subprocess.run(['usermod', '-L', username], check=True)
        subprocess.run(['usermod', '-s', '/sbin/nologin', username], check=True)

        update_opt_out(username)

        os.makedirs(os.path.dirname(DEACTIVATED_LOG), exist_ok=True)
        with open(DEACTIVATED_LOG, 'a') as f:
            f.write(f"{username} deactivated via email at {datetime.datetime.now()}\n")

        return f"❌ Your account '{username}' has been deactivated and will not be prompted again."
    except Exception as e:
        return f"⚠️ Failed to deactivate account '{username}': {e}"

@app.route('/')
def index():
    return "🛡️ Dormant Account Manager Running"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
