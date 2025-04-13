#! /bin/bash
# Opalstack Hugo Demo Site installer.
# Takes token and app info, uses env vars passed into the context by the Opalstack API
# and launchers, installs a user-only version of Go and Hugo extended, and then creates
# a demo Hugo site.
#
# Order of operations:
# 1. External downloads: tarballs and theme submodules.
# 2. API calls: validate the app, get account info.
# 3. Application logic: install Go, install Hugo, and create a demo site.

# Color definitions for output
CRED2='\033[1;91m'        # Red
CGREEN2='\033[1;92m'      # Green
CYELLOW2='\033[1;93m'     # Yellow
CBLUE2='\033[1;94m'       # Blue
CVIOLET2='\033[1;95m'     # Purple
CCYAN2='\033[1;96m'       # Cyan
CWHITE2='\033[1;97m'      # White
CEND='\033[0m'            # Text Reset

# Parse command-line options: -i for UUID and -n for APPNAME.
while getopts i:n: option
do
    case "${option}" in
        i) UUID=${OPTARG};;
        n) APPNAME=${OPTARG};;
    esac
done

# Log start time
printf 'Started at %(%F %T)T\n' >> /home/$USER/logs/apps/$APPNAME/install.log

# Ensure required parameters are provided
if [ -z "$UUID" ] || [ -z "$OPAL_TOKEN" ] || [ -z "$APPNAME" ]
then
    printf "${CRED2}"
    echo "This command requires the following parameters to function:
    -i App UUID, used to make API calls to the control panel.
    -n Application NAME, must match the name in the control panel.
    \$OPAL_TOKEN: Control panel token, used to authenticate to the API.
    \$API_URL: API endpoint.
    "
    exit 1
fi

# Validate app UUID and fetch server info
if serverjson=$(curl -s --fail --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" "$API_URL/api/v1/app/read/$UUID")
then
    printf "${CGREEN2}"
    echo "UUID validation and server lookup OK."
    printf "${CEND}"
    serverid=$(echo "$serverjson" | jq -r .server)
else
    printf "${CRED2}"
    echo "UUID validation and server lookup failed."
    exit 1
fi

# Get the account email address
if accountjson=$(curl -s --fail --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" "$API_URL/api/v1/account/info/")
then
    printf "${CGREEN2}"
    echo "Admin email lookup OK."
    printf "${CEND}"
    accountemail=$(echo "$accountjson" | jq -r .email)
else
    printf "${CRED2}"
    echo "Admin email lookup failed."
    exit 1
fi

# ------------------------------
# Install Go and Hugo Demo Site
# ------------------------------

# Set Go version to install
GO_VERSION=1.23.0

# Ensure ~/bin exists (we install binaries here)
mkdir -p "$HOME/bin"

# Download and install Go in the user environment
cd "$HOME"
echo "Downloading Go ${GO_VERSION}..."
curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
echo "Extracting Go..."
tar -xzf go${GO_VERSION}.linux-amd64.tar.gz
mv go .go-${GO_VERSION}
rm go${GO_VERSION}.linux-amd64.tar.gz

# Set Go environment variables for this session
export GOROOT="$HOME/.go-${GO_VERSION}"
export GOPATH="$HOME/.gopath"
export PATH="$GOROOT/bin:$GOPATH/bin:$HOME/bin:$PATH"

# Create GOPATH bin directory if it does not exist
mkdir -p "$GOPATH/bin"

# Confirm installation of Go
echo "Go version:"
go version

# Install Hugo extended (with deploy support)
echo "Installing Hugo extended..."
CGO_ENABLED=1 go install -tags extended,withdeploy github.com/gohugoio/hugo@latest

# Move Hugo binary to ~/bin so that it’s in a predictable location
mv "$GOPATH/bin/hugo" "$HOME/bin/"

# Confirm installation of Hugo
echo "Hugo version:"
"$HOME/bin/hugo" version

# ------------------------------
# Create the Hugo Demo Site
# ------------------------------

# Define the directory for the Hugo site
SITE_DIR="$HOME/apps/$APPNAME"
mkdir -p "$SITE_DIR"
cd "$SITE_DIR"

# Create a new Hugo site (named demo-site) if it doesn't already exist
if [ ! -d "demo-site" ]; then
    echo "Creating new Hugo site demo-site..."
    "$HOME/bin/hugo" new site demo-site
else
    echo "Hugo site demo-site already exists. Skipping site creation."
fi

cd demo-site

# Initialize a Git repository (required for adding a theme as a submodule)
if [ ! -d ".git" ]; then
    git init
fi

# Add the Ananke theme submodule if it is not already present and set it as the site theme
if [ ! -d "themes/ananke" ]; then
    echo "Adding Ananke theme..."
    git submodule add https://github.com/theNewDynamic/gohugo-theme-ananke.git themes/ananke
    # Append theme configuration to config.toml; create it if it doesn't exist.
    if [ ! -f config.toml ]; then
        touch config.toml
    fi
    echo 'theme = "ananke"' >> config.toml
fi

# Create a sample post for the demo
echo "Creating a sample post..."
"$HOME/bin/hugo" new posts/my-first-post.md

# Build the site to verify it works
echo "Building Hugo site..."
"$HOME/bin/hugo"

# Installation complete message
printf "${CGREEN2}"
echo "Hugo demo site installation complete."
printf "${CEND}"

# ------------------------------
# Notify Opalstack API that the app is installed
# ------------------------------

curl -s -X POST --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" \
     -d'[{"id": "'$UUID'"}]' "$API_URL/api/v1/app/installed/"

# Create an installation notice via the API
curl -s -X POST --header "Content-Type:application/json" --header "Authorization: Token $OPAL_TOKEN" \
     -d'[{"type": "D", "content":"Created Hugo demo site '$APPNAME' with Admin: '$USER' and email: '$accountemail'"}]' "$API_URL/api/v1/notice/create/"
