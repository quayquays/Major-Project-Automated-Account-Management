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

def load_token_secret():
    with open(TOKEN_SECRET_CONF, 'r') as f:
        for line in f:
            if line.startswith("TOKEN_SECRET="):
                return line.strip().split('=', 1)[1].strip().strip('"').strip("'")
    raise Exception("TOKEN_SECRET not found in /etc/token_secret.conf")

TOKEN_SECRET = load_token_secret()

RESET_FORM_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Reset Password</title>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600&display=swap" rel="stylesheet">
  <style>
    body {
      margin: 0;
      padding: 0;
      font-family: 'Poppins', sans-serif;
      background: #f0f2f5;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
    }
    .container {
      background: #fff;
      padding: 2rem;
      border-radius: 16px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
      width: 100%;
      max-width: 400px;
    }
    h2 {
      text-align: center;
      font-weight: 600;
      margin-bottom: 1.5rem;
    }
    label {
      display: block;
      margin-bottom: 0.5rem;
      font-weight: 500;
    }
    input[type="password"] {
      width: 100%;
      padding: 0.75rem;
      margin-bottom: 1.25rem;
      border: 1px solid #ccc;
      border-radius: 8px;
      font-size: 1rem;
    }
    input[type="submit"] {
      width: 100%;
      padding: 0.75rem;
      background-color: #7c3aed;
      color: white;
      font-weight: bold;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      transition: background-color 0.3s ease;
    }
    input[type="submit"]:hover {
      background-color: #6d28d9;
    }
    .msg {
      text-align: center;
      color: #333;
      margin-top: 1rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>🔐 Reset Password</h2>
    <form method="POST">
      <input type="hidden" name="user" value="{{ user }}">
      <label for="password">New Password</label>
      <input type="password" name="password" id="password" required>

      <label for="confirm_password">Confirm Password</label>
      <input type="password" name="confirm_password" id="confirm_password" required>

      <input type="submit" value="Update Password">
    </form>
    {% if message %}
    <div class="msg">{{ message }}</div>
    {% endif %}
  </div>
</body>
</html>
'''

MESSAGE_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Account Notification</title>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600&display=swap" rel="stylesheet">
  <style>
    body {
      margin: 0;
      padding: 0;
      font-family: 'Poppins', sans-serif;
      background: #f0f2f5;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
    }
    .container {
      background: #fff;
      padding: 2rem;
      border-radius: 16px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
      width: 100%;
      max-width: 500px;
      text-align: center;
    }
    .status-icon {
      font-size: 3rem;
      margin-bottom: 1rem;
    }
    .message {
      font-size: 1.1rem;
      color: #333;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="status-icon">{{ icon }}</div>
    <div class="message">{{ message }}</div>
  </div>
</body>
</html>
'''

def read_submissions():
    submissions = {}
    if os.path.exists(SUBMISSIONS_FILE):
        with open(SUBMISSIONS_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    user, response = line.split('=', 1)
                    submissions[user] = response
    return submissions

def write_submission(user, response):
    submissions = read_submissions()
    submissions[user] = response
    os.makedirs(os.path.dirname(SUBMISSIONS_FILE), exist_ok=True)
    with open(SUBMISSIONS_FILE, 'w') as f:
        for u, r in submissions.items():
            f.write(f"{u}={r}\n")

def verify_token(user, token):
    try:
        hmac_part, timestamp = token.split(':', 1)
    except ValueError:
        return False

    msg = f"{user}:{timestamp}".encode()
    key = TOKEN_SECRET.encode()
    expected_hmac = hmac.new(key, msg, hashlib.sha256).digest()
    expected_token = base64.urlsafe_b64encode(expected_hmac).rstrip(b'=').decode()

    return hmac.compare_digest(hmac_part, expected_token)

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
        return render_template_string(MESSAGE_HTML, icon="⚠️", message="Missing user, token, or invalid response."), 400

    if not verify_token(user, token):
        return render_template_string(MESSAGE_HTML, icon="❌", message="Invalid or expired token."), 403

    submissions = read_submissions()
    if user in submissions:
        return render_template_string(MESSAGE_HTML, icon="⚠️", message="You have already submitted your choice.")

    if response == 'yes':
        write_submission(user, 'yes')
        return redirect(url_for('reset_password', user=user))
    else:
        try:
            deactivate_user(user)
            write_submission(user, 'no')
            return render_template_string(MESSAGE_HTML, icon="✅", message=f"Your account '{user}' has been deactivated.")
        except Exception as e:
            return render_template_string(MESSAGE_HTML, icon="⚠️", message=f"Error deactivating account: {e}"), 500

@app.route('/reset_password', methods=['GET', 'POST'])
def reset_password():
    user = request.args.get('user') or request.form.get('user')
    if not user:
        return render_template_string(MESSAGE_HTML, icon="⚠️", message="Missing user."), 400

    submissions = read_submissions()
    if user not in submissions or submissions[user] != "yes":
        return render_template_string(MESSAGE_HTML, icon="⚠️", message="Invalid or expired password reset link."), 400

    if request.method == 'GET':
        return render_template_string(
            RESET_FORM_HTML,
            user=user,
            message="You must update your password to renew your dormancy period."
        )

    password = request.form.get('password')
    confirm = request.form.get('confirm_password')

    if not password or not confirm:
        return render_template_string(
            RESET_FORM_HTML,
            user=user,
            message="⚠️ Please fill both password fields."
        )
    if password != confirm:
        return render_template_string(
            RESET_FORM_HTML,
            user=user,
            message="❌ Passwords do not match."
        )

    try:
        subprocess.run(['bash', '-c', f'echo "{user}:{password}" | chpasswd'], check=True)
        today_str = datetime.datetime.now().strftime("%Y-%m-%d")
        subprocess.run(['chage', '-d', today_str, user], check=True)
        subprocess.run(['chage', '-E', '-1', user], check=True)
        subprocess.run(['usermod', '-s', '/bin/bash', user], check=True)
        write_opt_in_date(user)

        return redirect(url_for('reactivated', user=user))

    except Exception as e:
        return render_template_string(
            RESET_FORM_HTML,
            user=user,
            message=f"⚠️ Error updating password: {e}"
        )

@app.route('/reactivated')
def reactivated():
    user = request.args.get('user')
    if not user:
        return render_template_string(MESSAGE_HTML, icon="⚠️", message="Missing user.")
    return render_template_string(
        MESSAGE_HTML,
        icon="✅",
        message=f"User '{user}' has been reactivated. Please log in. Thanks!"
    )

@app.route('/')
def index():
    return "🛡️ Dormant Account Manager Running"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
