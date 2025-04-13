#! /bin/bash
# Opalstack Jekyl installer.
# Takes token and app info, validates via control panel API,
# then uses Docker to build and install a new Jekyll site in userspace.
#
# Order of operations best practice:
#   1. External downloads (e.g. pulling Docker images).
#   2. API calls to control panel for app validation and admin info.
#   3. Application creation via Docker commands.
#
# Color definitions for terminal output.
CRED2='\033[1;91m'        # Red
CGREEN2='\033[1;92m'      # Green
CYELLOW2='\033[1;93m'     # Yellow
CBLUE2='\033[1;94m'       # Blue
CVIOLET2='\033[1;95m'     # Purple
CCYAN2='\033[1;96m'       # Cyan
CWHITE2='\033[1;97m'      # White
CEND='\033[0m'           # Text Reset

# Parse command line arguments.
#   -i App UUID (used for API calls to the control panel)
#   -n Application NAME (must match the name in the control panel)
while getopts i:n: option
do
    case "${option}" in
        i) UUID=${OPTARG};;
        n) APPNAME=${OPTARG};;
    esac
done

# Log installation start time.
printf 'Started at %(%F %T)T\n' >> /home/$USER/logs/apps/$APPNAME/install.log

# Validate required parameters.
if [ -z "$UUID" ] || [ -z "$OPAL_TOKEN" ] || [ -z "$APPNAME" ]; then
    printf "${CRED2}"
    echo 'Error: This command requires the following parameters:
    -i App UUID, used to make API calls to the control panel.
    -n Application NAME, must match the name in the control panel.
    The environment variable {OPAL_TOKEN} must also be set.'
    printf "${CEND}"
    exit 1
fi

# Validate the app by retrieving server details.
if serverjson=$(curl -s --fail \
    --header "Content-Type:application/json" \
    --header "Authorization: Token $OPAL_TOKEN" \
    "$API_URL/api/v1/app/read/$UUID"); then
    printf "${CGREEN2}"
    echo 'UUID validation and server lookup OK.'
    printf "${CEND}"
    serverid=$(echo "$serverjson" | jq -r .server)
else
    printf "${CRED2}"
    echo 'UUID validation and server lookup failed.'
    printf "${CEND}"
    exit 1
fi

# Retrieve the account's admin email for notifications.
if accountjson=$(curl -s --fail \
    --header "Content-Type:application/json" \
    --header "Authorization: Token $OPAL_TOKEN" \
    "$API_URL/api/v1/account/info/"); then
    printf "${CGREEN2}"
    echo 'Admin email lookup OK.'
    printf "${CEND}"
    accountemail=$(echo "$accountjson" | jq -r .email)
else
    printf "${CRED2}"
    echo 'Admin email lookup failed.'
    printf "${CEND}"
    exit 1
fi

# Create the application directory.
APP_PATH="/home/$USER/apps/$APPNAME"
mkdir -p "$APP_PATH"
printf "${CYELLOW2}"
echo "Application directory created at $APP_PATH"
printf "${CEND}"

# Pull the official Jekyll image (optional; docker will pull it if needed).
printf "${CBLUE2}"
echo "Pulling the latest Jekyll Docker image..."
printf "${CEND}"
docker pull jekyll/jekyll

# Use Docker to create a new Jekyll site inside the app directory.
printf "${CCYAN2}"
echo "Starting Jekyll site creation using Docker..."
printf "${CEND}"
docker run --rm -v "$APP_PATH":/srv/jekyll jekyll/jekyll jekyll new /srv/jekyll

if [ $? -eq 0 ]; then
    printf "${CGREEN2}"
    echo "Jekyll site created successfully in $APP_PATH."
    printf "${CEND}"
else
    printf "${CRED2}"
    echo "Jekyll site creation failed."
    printf "${CEND}"
    exit 1
fi

# (Optional) Build the static site using Docker.
printf "${CBLUE2}"
echo "Building the Jekyll site using Docker..."
printf "${CEND}"
docker run --rm -v "$APP_PATH":/srv/jekyll -w /srv/jekyll jekyll/jekyll jekyll build

# Notify control panel that the application has been installed.
curl -s -X POST \
    --header "Content-Type:application/json" \
    --header "Authorization: Token $OPAL_TOKEN" \
    -d'[{"id": "'"$UUID"'"}]' \
    "$API_URL/api/v1/app/installed/"

# Create installation notice.
curl -s -X POST \
    --header "Content-Type:application/json" \
    --header "Authorization: Token $OPAL_TOKEN" \
    -d'[{"type": "D", "content": "Created Jekyll app '"$APPNAME"' for User: '"$USER"' with server id: '"$serverid"'"}]' \
    "$API_URL/api/v1/notice/create/"

printf "${CGREEN2}"
echo "Opalstack Jekyl installer finished successfully."
printf "${CEND}"
