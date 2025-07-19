from flask import Flask, request, redirect, url_for, render_template_string
import hmac
import hashlib
import base64
import datetime
import os
import subprocess

app = Flask(__name__)

OPT_IN_FILE = "/etc/dormant_opt_in.conf"
DEACTIVATED_LOG = "/var/log/dormant/deactivated_users.log"
SUBMISSIONS_FILE = "/etc/dormant_submissions.conf"
TOKEN_SECRET_CONF = "/etc/token_secret.conf"

# Load token secret from file
def load_token_secret():
    with open(TOKEN_SECRET_CONF, 'r') as f:
        for line in f:
            if line.startswith("TOKEN_SECRET="):
                return line.strip().split('=', 1)[1].strip().strip('"').strip("'")
    raise Exception("TOKEN_SECRET not found in /etc/token_secret.conf")

TOKEN_SECRET = load_token_secret()

# Password reset form HTML
RESET_FORM_HTML = '''
<h2>🔐 Reset Password for {{ user }}</h2>
<form method="POST">
  <input type="hidden" name="user" value="{{ user }}">
  <label>New Password:</label><br>
  <input type="password" name="password" required><br><br>
  <label>Confirm Password:</label><br>
  <input type="password" name="confirm_password" required><br><br>
  <input type="submit" value="Update Password">
</form>
'''

# Helpers to read/write submission status to block reuse
def read_submissions():
    submissions = {}
    if os.path.exists(SUBMISSIONS_FILE):
        with open(SUBMISSIONS_FILE, 'r') as f:
            for line in f:
                line=line.strip()
                if '=' in line:
                    user, response = line.split('=',1)
                    submissions[user] = response
    return submissions

def write_submission(user, response):
    submissions = read_submissions()
    submissions[user] = response
    os.makedirs(os.path.dirname(SUBMISSIONS_FILE), exist_ok=True)
    with open(SUBMISSIONS_FILE, 'w') as f:
        for u, r in submissions.items():
            f.write(f"{u}={r}\n")

# Token verification function
def verify_token(user, token):
    try:
        hmac_part, timestamp = token.split(':',1)
    except ValueError:
        return False

    msg = f"{user}:{timestamp}".encode()
    key = TOKEN_SECRET.encode()

    expected_hmac = hmac.new(key, msg, hashlib.sha256).digest()
    expected_token = base64.urlsafe_b64encode(expected_hmac).rstrip(b'=').decode()

    return hmac.compare_digest(hmac_part, expected_token)

# Write opt-in date for user
def write_opt_in_date(user):
    now = datetime.datetime.now().strftime("%Y-%m-%d")
    os.makedirs(os.path.dirname(OPT_IN_FILE), exist_ok=True)
    lines = []
    if os.path.exists(OPT_IN_FILE):
        with open(OPT_IN_FILE, 'r') as f:
            lines = f.readlines()
    with open(OPT_IN_FILE, 'w') as f:
        for line in lines:
            if not line.startswith(f"{user}="):
                f.write(line)
        f.write(f"{user}={now}\n")

# Deactivate user function
def deactivate_user(user):
    try:
        subprocess.run(['usermod', '-L', user], check=True)
        subprocess.run(['usermod', '-s', '/sbin/nologin', user], check=True)
        os.makedirs(os.path.dirname(DEACTIVATED_LOG), exist_ok=True)
        with open(DEACTIVATED_LOG, 'a') as f:
            f.write(f"{datetime.datetime.now()} - User '{user}' deactivated via email link\n")
    except Exception as e:
        raise RuntimeError(f"Failed to deactivate user {user}: {e}")

@app.route('/confirm')
def confirm():
    user = request.args.get('user')
    token = request.args.get('token')
    response = request.args.get('response')

    if not user or not token or response not in ('yes', 'no'):
        return "⚠️ Missing user, token, or invalid response.", 400

    if not verify_token(user, token):
        return "❌ Invalid or expired token.", 403

    submissions = read_submissions()
    if user in submissions:
        return "⚠️ You have already submitted your choice."

    if response == 'yes':
        write_submission(user, 'yes')
        # Redirect to password reset page with message to update password
        return redirect(url_for('reset_password', user=user))
    else:  # response == 'no'
        try:
            deactivate_user(user)
            write_submission(user, 'no')
            return f"❌ Your account '{user}' has been deactivated."
        except Exception as e:
            return f"⚠️ Error deactivating account: {e}", 500

@app.route('/reset_password', methods=['GET', 'POST'])
def reset_password():
    user = request.args.get('user') or request.form.get('user')
    if not user:
        return "⚠️ Missing user.", 400

    submissions = read_submissions()
    if user not in submissions or submissions[user] != "yes":
        return "⚠️ Invalid or expired password reset link.", 400

    if request.method == 'GET':
        msg = "You must update your password to renew your dormancy period."
        return render_template_string(RESET_FORM_HTML + f"<p style='color:blue;'>{msg}</p>", user=user)

    # POST: process form submission
    password = request.form.get('password')
    confirm = request.form.get('confirm_password')

    if not password or not confirm:
        return "⚠️ Please fill both password fields.", 400
    if password != confirm:
        return "❌ Passwords do not match.", 400

    try:
        # Reset password
        subprocess.run(['bash', '-c', f'echo "{user}:{password}" | chpasswd'], check=True)
        # Reset password last change date to today
        today_str = datetime.datetime.now().strftime("%Y-%m-%d")
        subprocess.run(['chage', '-d', today_str, user], check=True)
        # Remove account expiration date (never expire)
        subprocess.run(['chage', '-E', '-1', user], check=True)
        # Reset shell to /bin/bash to allow login
        subprocess.run(['usermod', '-s', '/bin/bash', user], check=True)
        # Update opt-in date to now to reset dormancy
        write_opt_in_date(user)

        success_msg = f"✅ Password updated successfully for {user}. Your dormancy period has been reset. You may now log in."
        return success_msg
    except Exception as e:
        return f"⚠️ Error updating password: {e}", 500

@app.route('/')
def index():
    return "🛡️ Dormant Account Manager Running"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
