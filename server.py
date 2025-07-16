from flask import Flask, request, render_template_string, redirect, url_for
import os
import datetime
import subprocess

app = Flask(__name__)

OPT_IN_FILE = "/etc/dormant_opt_in.conf"
DEACTIVATED_LOG = "/var/log/dormant/deactivated_users.log"

RESET_FORM_HTML = '''
<h2>🔐 Reset Password for {{ user }}</h2>
<form method="POST">
  <input type="hidden" name="user" value="{{ user }}">
  <label>New Password:</label><br>
  <input type="password" name="password"><br><br>
  <label>Confirm Password:</label><br>
  <input type="password" name="confirm_password"><br><br>
  <input type="submit" value="Update Password">
</form>
'''

@app.route('/confirm')
def confirm():
    user = request.args.get('user')
    response = request.args.get('response')

    if response == "yes" and user:
        now = datetime.datetime.now().strftime("%Y-%m-%d")
        os.makedirs(os.path.dirname(OPT_IN_FILE), exist_ok=True)

        # Remove any existing opt-in for the user
        lines = []
        if os.path.exists(OPT_IN_FILE):
            with open(OPT_IN_FILE, 'r') as f:
                lines = f.readlines()

        with open(OPT_IN_FILE, 'w') as f:
            for line in lines:
                if not line.startswith(f"{user}="):
                    f.write(line)
            f.write(f"{user}={now}\n")

        # Redirect to password reset form
        return redirect(url_for('reset_password', user=user))
    else:
        return "⚠️ Missing user or invalid response.", 400

@app.route('/reset_password', methods=['GET', 'POST'])
def reset_password():
    user = request.args.get('user') or request.form.get('user')

    if request.method == 'GET':
        if not user:
            return "⚠️ Missing user.", 400
        return render_template_string(RESET_FORM_HTML, user=user)

    password = request.form.get('password')
    confirm = request.form.get('confirm_password')

    if not password or not confirm:
        return "⚠️ Please fill out both fields.", 400
    if password != confirm:
        return "❌ Passwords do not match.", 400

    try:
        # Update password
        subprocess.run(['bash', '-c', f'echo "{user}:{password}" | chpasswd'], check=True)
        # Set last password change date to today (no forced change)
        today_str = datetime.datetime.now().strftime("%Y-%m-%d")
        subprocess.run(['chage', '-d', today_str, user], check=True)

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
