#! /bin/bash
# Opalstack Jekyll Demo Site Installer
#
# This installer will:
#  1. Validate parameters and connect to the Opalstack API.
#  2. Install Jekyll and Bundler into the user environment using RubyGems (--user-install).
#  3. Create a new Jekyll demo site with a sample post.
#  4. Build the site to verify that it “just works.”
#  5. Notify the Opalstack API upon successful installation.
#
# Usage:
#   ./installer.sh -i <APP_UUID> -n <APPNAME>
#
# Required environment variables:
#   OPAL_TOKEN  - Control panel token for API authentication.
#   API_URL     - The endpoint for the Opalstack API.

# Color definitions for output
CRED2='\033[1;91m'        # Red
CGREEN2='\033[1;92m'      # Green
CYELLOW2='\033[1;93m'     # Yellow
CBLUE2='\033[1;94m'       # Blue
CVIOLET2='\033[1;95m'     # Purple
CCYAN2='\033[1;96m'       # Cyan
CWHITE2='\033[1;97m'      # White
CEND='\033[0m'            # Text Reset

# Parse command-line options: -i for UUID and -n for APPNAME
while getopts i:n: option; do
    case "${option}" in
        i) UUID=${OPTARG};;
        n) APPNAME=${OPTARG};;
    esac
done

# Log the start time for tracking
LOGFILE="/home/$USER/logs/apps/$APPNAME/install.log"
printf 'Started at %(%F %T)T\n' >> "$LOGFILE"

# Ensure all required parameters are provided
if [ -z "$UUID" ] || [ -z "$OPAL_TOKEN" ] || [ -z "$APPNAME" ] || [ -z "$API_URL" ]; then
    printf "${CRED2}"
    echo "This command requires the following parameters to function:
    -i App UUID, used to make API calls to the control panel.
    -n Application NAME, must match the name in the control panel.
    OPAL_TOKEN: Control panel token, used for API authentication.
    API_URL: The API endpoint.
    "
    exit 1
fi

# Validate the app UUID and lookup server details
if serverjson=$(curl -s --fail --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" "$API_URL/api/v1/app/read/$UUID"); then
    printf "${CGREEN2}"
    echo "UUID validation and server lookup OK."
    printf "${CEND}"
    serverid=$(echo "$serverjson" | jq -r .server)
else
    printf "${CRED2}"
    echo "UUID validation and server lookup failed."
    exit 1
fi

# Get the admin account email
if accountjson=$(curl -s --fail --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" "$API_URL/api/v1/account/info/"); then
    printf "${CGREEN2}"
    echo "Admin email lookup OK."
    printf "${CEND}"
    accountemail=$(echo "$accountjson" | jq -r .email)
else
    printf "${CRED2}"
    echo "Admin email lookup failed."
    exit 1
fi

# ------------------------------------------------------------
# Jekyll and Demo Site Installation: Let’s do it up for Jek yas!
# ------------------------------------------------------------

echo "Installing Jekyll and Bundler into your user environment..."

# Install Jekyll and Bundler using RubyGems with --user-install (assumes Ruby is installed)
gem install jekyll bundler --user-install

# Set up the PATH to include the Ruby user gem binaries.
# This uses Ruby to determine the gem user directory.
export GEM_USER_DIR=$(ruby -r rubygems -e 'puts Gem.user_dir')
export PATH="$GEM_USER_DIR/bin:$PATH"

# Confirm installation of Jekyll
echo "Jekyll version installed:"
jekyll -v

# Create an apps directory and set up the demo site location.
SITE_ROOT="$HOME/apps/$APPNAME"
mkdir -p "$SITE_ROOT"
cd "$SITE_ROOT"

# Create a new Jekyll site called demo-site if it doesn't already exist.
if [ ! -d "demo-site" ]; then
    echo "Creating new Jekyll site 'demo-site'..."
    jekyll new demo-site
else
    echo "Jekyll site 'demo-site' already exists. Skipping creation."
fi

cd demo-site

# Create a demo post in the _posts directory.
POST_DATE=$(date +%F)
POST_FILE="_posts/${POST_DATE}-welcome-to-jekyll.md"
if [ ! -f "$POST_FILE" ]; then
    echo "Creating a sample demo post..."
    cat <<EOF > "$POST_FILE"
---
layout: post
title:  "Welcome to Jekyll"
date:   $(date +'%Y-%m-%d %H:%M:%S %z')
categories: jekyll demo
---
Hey there! This is your first post on a brand new Jekyll site. Let's get jek yas!
EOF
else
    echo "Sample demo post already exists, skipping."
fi

# Build the site to ensure it works.
echo "Building the Jekyll site..."
bundle exec jekyll build

echo -e "${CGREEN2}Jekyll demo site installation complete.${CEND}"

# ------------------------------------------------------------
# Notify the Opalstack API that the installation is complete.
# ------------------------------------------------------------

# Notify that the app is installed
curl -s -X POST --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" \
     -d'[{"id": "'$UUID'"}]' "$API_URL/api/v1/app/installed/"

# Create an installation notice via the Opalstack API.
curl -s -X POST --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" \
     -d'[{"type": "D", "content":"Created Jekyll demo site '$APPNAME' with Admin: '$USER' and email: '$accountemail'"}]' "$API_URL/api/v1/notice/create/"
