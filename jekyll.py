#! /bin/python3

import argparse
import sys
import logging
import os
import os.path
import http.client
import json
import textwrap
import secrets
import string
import subprocess
import shlex
import random
from urllib.parse import urlparse
import urllib.request
import datetime

# Get API host from env variables. Strip protocol if set.
API_HOST = os.environ.get('API_URL', 'https://my.opalstack.com').strip('https://').strip('http://')
API_BASE_URI = '/api/v1'
CMD_ENV = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'UMASK': '0002'}

class OpalstackAPITool():
    """Simple wrapper for HTTP GET and POST calls to the Opalstack API."""
    def __init__(self, host, base_uri, authtoken, user, password):
        self.host = host
        self.base_uri = base_uri

        # if no auth token provided, try logging in with credentials
        if not authtoken:
            endpoint = self.base_uri + '/login/'
            payload = json.dumps({
                'username': user,
                'password': password
            })
            conn = http.client.HTTPSConnection(self.host)
            conn.request('POST', endpoint, payload,
                         headers={'Content-type': 'application/json'})
            result = json.loads(conn.getresponse().read())
            if not result.get('token'):
                logging.warning('Invalid username or password and no auth token provided, exiting.')
                sys.exit(1)
            else:
                authtoken = result['token']

        self.headers = {
            'Content-type': 'application/json',
            'Authorization': f'Token {authtoken}'
        }

    def get(self, endpoint):
        """GET an API endpoint."""
        endpoint = self.base_uri + endpoint
        conn = http.client.HTTPSConnection(self.host)
        conn.request('GET', endpoint, headers=self.headers)
        return json.loads(conn.getresponse().read())

    def post(self, endpoint, payload):
        """POST data to an API endpoint."""
        endpoint = self.base_uri + endpoint
        conn = http.client.HTTPSConnection(self.host)
        conn.request('POST', endpoint, payload, headers=self.headers)
        return json.loads(conn.getresponse().read())

def run_command(cmd, env, cwd=None):
    """Run a command and return its output."""
    logging.info(f'Running: {cmd}')
    try:
        result = subprocess.check_output(shlex.split(cmd), cwd=cwd, env=env)
    except subprocess.CalledProcessError as e:
        logging.debug(e.output)
        result = e.output
    return result

def create_file(path, contents, writemode='w', perms=0o600):
    """Create a file with specific contents and permissions."""
    with open(path, writemode) as f:
        f.write(contents)
    os.chmod(path, perms)
    logging.info(f'Created file {path} with permissions {oct(perms)}')

def download(url, localfile, writemode='wb', perms=0o600):
    """Download a remote file and set its permissions."""
    logging.info(f'Downloading {url} as {localfile} with permissions {oct(perms)}')
    urllib.request.urlretrieve(url, filename=localfile)
    os.chmod(localfile, perms)
    logging.info(f'Downloaded {url} as {localfile} with permissions {oct(perms)}')

def gen_password(length=20):
    """Generate a random password."""
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for i in range(length))

def add_cronjob(cronjob, env):
    """Append a cron job to the user's crontab."""
    homedir = os.path.expanduser('~')
    tmpname = f'{homedir}/.tmp{gen_password()}'
    with open(tmpname, 'w') as tmp:
        # Get current crontab output if any
        try:
            current = run_command('crontab -l', env).decode()
        except Exception as ex:
            current = ''
        tmp.write(current)
        tmp.write(f'{cronjob}\n')
    run_command(f'crontab {tmpname}', env)
    run_command(f'rm -f {tmpname}', env)
    logging.info(f'Added cron job: {cronjob}')

def main():
    """Main installation routine."""
    # Set up argument parsing from CLI or environment variables.
    parser = argparse.ArgumentParser(
        description='Installs a Jekyll demo site on an Opalstack account')
    parser.add_argument('-i', dest='app_uuid', help='UUID of the base app', 
                        default=os.environ.get('UUID'))
    parser.add_argument('-n', dest='app_name', help='Name of the base app', 
                        default=os.environ.get('APPNAME'))
    parser.add_argument('-t', dest='opal_token', help='API auth token', 
                        default=os.environ.get('OPAL_TOKEN'))
    parser.add_argument('-u', dest='opal_user', help='Opalstack account name', 
                        default=os.environ.get('OPAL_USER'))
    parser.add_argument('-p', dest='opal_password', help='Opalstack account password', 
                        default=os.environ.get('OPAL_PASS'))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO,
                        format='[%(asctime)s] %(levelname)s: %(message)s')
    logging.info(f'Started installation of Jekyll demo site {args.app_name}')

    # Initialize API tool
    api = OpalstackAPITool(API_HOST, API_BASE_URI, args.opal_token, args.opal_user, args.opal_password)
    appinfo = api.get(f'/app/read/{args.app_uuid}')
    osuser = appinfo["osuser_name"]
    appname = appinfo["name"]
    # Define the app directory; adjust if needed.
    appdir = f'/home/{osuser}/apps/{appname}'
    if not os.path.exists(appdir):
        os.makedirs(appdir, exist_ok=True)
    # Create a temporary directory under the app directory
    tmpdir = os.path.join(appdir, 'tmp')
    os.makedirs(tmpdir, exist_ok=True)

    # Update CMD_ENV with settings for this app
    CMD_ENV.update({
        'TMPDIR': tmpdir,
        'GEM_HOME': tmpdir,
        'HOME': f'/home/{osuser}'
    })
    # The PATH will be augmented later with the gem user's bin

    # ------------------------------
    # Install Jekyll and Bundler
    # ------------------------------
    logging.info("Installing Jekyll and Bundler with --user-install")
    # Run gem install command in appdir
    run_command("gem install jekyll bundler --user-install", CMD_ENV, cwd=appdir)

    # Determine the Ruby gem user directory
    gem_user_dir = run_command("ruby -r rubygems -e 'puts Gem.user_dir'", CMD_ENV, cwd=appdir).decode().strip()
    logging.info(f"Gem user directory: {gem_user_dir}")
    # Update PATH to include the gem user bin directory
    CMD_ENV['PATH'] = f"{gem_user_dir}/bin:" + CMD_ENV['PATH']
    
    # Confirm Jekyll installation
    jekyll_version = run_command("jekyll -v", CMD_ENV, cwd=appdir).decode().strip()
    logging.info(f"Jekyll version: {jekyll_version}")

    # ------------------------------
    # Create the Jekyll Demo Site
    # ------------------------------
    site_dir = os.path.join(appdir, "demo-site")
    if not os.path.isdir(site_dir):
        logging.info("Creating a new Jekyll site 'demo-site'...")
        run_command("jekyll new demo-site", CMD_ENV, cwd=appdir)
    else:
        logging.info("Jekyll site 'demo-site' already exists. Skipping creation.")
    
    # Change directory to the site directory
    os.chdir(site_dir)
    
    # Create a sample post in the _posts directory
    posts_dir = os.path.join(site_dir, "_posts")
    if not os.path.isdir(posts_dir):
        os.makedirs(posts_dir)
    today = datetime.date.today().isoformat()
    post_filename = f"{today}-welcome-to-jekyll.md"
    post_path = os.path.join(posts_dir, post_filename)
    if not os.path.exists(post_path):
        logging.info("Creating a sample demo post...")
        sample_post = textwrap.dedent(f"""\
            ---
            layout: post
            title: "Welcome to Jekyll"
            date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S %z')}
            categories: jekyll demo
            ---
            Hey there! This is your first post on a brand new Jekyll site.
            Let's get jek yas!
            """)
        create_file(post_path, sample_post, perms=0o644)
    else:
        logging.info("Sample demo post already exists. Skipping.")
    
    # Build the site to verify installation
    logging.info("Building the Jekyll site...")
    run_command("bundle exec jekyll build", CMD_ENV, cwd=site_dir)

    # ------------------------------
    # Create Start and Stop Scripts
    # ------------------------------
    # Create a start script to run jekyll serve in the background.
    start_jekyll = textwrap.dedent(f"""\
        #!/bin/bash
        APPDIR={appdir}
        cd $APPDIR/demo-site
        # Start Jekyll serve in the background and write the PID to a file.
        nohup bundle exec jekyll serve > $APPDIR/demo-site/jekyll.log 2>&1 &
        echo $! > $APPDIR/demo-site/jekyll.pid
        echo "Jekyll server started."
        """)
    start_script_path = os.path.join(appdir, "start_jekyll")
    create_file(start_script_path, start_jekyll, perms=0o700)

    # Create a stop script to kill the jekyll serve process.
    stop_jekyll = textwrap.dedent(f"""\
        #!/bin/bash
        APPDIR={appdir}
        PIDFILE=$APPDIR/demo-site/jekyll.pid
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE")
            rm -f "$PIDFILE"
            echo "Jekyll server stopped."
        else
            echo "Jekyll server is not running (no PID file found)."
        fi
        """)
    stop_script_path = os.path.join(appdir, "stop_jekyll")
    create_file(stop_script_path, stop_jekyll, perms=0o700)

    # ------------------------------
    # Optionally, Add a Cron Job to Ensure the Jekyll Server is Running
    # ------------------------------
    m = random.randint(0,9)
    # This cron job will run periodically (you can adjust the schedule as needed)
    croncmd = f"0{m},1{m},2{m},3{m},4{m},5{m} * * * * {appdir}/start_jekyll > /dev/null 2>&1"
    add_cronjob(croncmd, CMD_ENV)

    # ------------------------------
    # Create a README with Post-Install Instructions
    # ------------------------------
    readme = textwrap.dedent(f"""\
        # Opalstack Jekyll Demo Site README

        ## Post-install Steps

        1. To preview your Jekyll site, execute:
        
               {appdir}/start_jekyll

           This will start the Jekyll server (running in the background).

        2. To stop the server, execute:
        
               {appdir}/stop_jekyll

        3. Your generated site files are located in:
        
               {appdir}/demo-site/_site

        4. Edit your Jekyll site by modifying files in the demo-site directory.
           To add more posts, add markdown files to the demo-site/_posts directory.

        5. For further customization, refer to the [Jekyll documentation](https://jekyllrb.com/docs/).

        Enjoy your new Jekyll demo site!
        """)
    readme_path = os.path.join(appdir, "README")
    create_file(readme_path, readme, perms=0o644)

    # ------------------------------
    # Notify Opalstack API That the App is Installed
    # ------------------------------
    payload = json.dumps([{'id': args.app_uuid}])
    finished = api.post('/app/installed/', payload)
    logging.info(f'Completed installation of Jekyll demo site {args.app_name}')

if __name__ == '__main__':
    main()
