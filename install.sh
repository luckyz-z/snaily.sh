#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[34mPlease run as root or with sudo.\e[0m"
  exit 1
fi

# Function to output in light blue
function print_light_blue {
  echo -e "\e[34m$1\e[0m"
}

# Ask for user input
print_light_blue "Please enter your CAD domain (e.g., cad.example.com):"
read CAD_DOMAIN

print_light_blue "Please enter your CAD API URL (e.g., https://cad-api.example.com/v1):"
read CAD_API_URL

# Installing dependencies
print_light_blue "Installing dependencies..."

# Update and upgrade while hiding output
apt update &>/dev/null && apt upgrade -y &>/dev/null
apt install -y npm nodejs postgresql postgresql-contrib curl git nginx certbot python3-certbot-nginx &>/dev/null

# Install NVM (Node Version Manager)
print_light_blue "Installing NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash &>/dev/null

# Source the shell configuration file to apply NVM changes without exiting
print_light_blue "Refreshing terminal environment to load NVM..."
source ~/.bashrc

# Install Node.js (version 20) after NVM is loaded
print_light_blue "Installing Node 20 with NVM..."
nvm install 20 &>/dev/null
nvm use 20 &>/dev/null

# Install pnpm globally
print_light_blue "Installing pnpm..."
npm install -g pnpm &>/dev/null

# Set up PostgreSQL
print_light_blue "Setting up PostgreSQL..."
sudo systemctl start postgresql &>/dev/null
sudo -i -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" &>/dev/null
sudo systemctl restart postgresql &>/dev/null

# Clone the SnailyCAD repository
print_light_blue "Cloning SnailyCAD repository..."
git clone https://github.com/SnailyCAD/snaily-cadv4.git &>/dev/null
cd snaily-cadv4

# Install dependencies using pnpm and show logs
print_light_blue "Installing dependencies for SnailyCAD..."
pnpm install | tee install.log

# Check if the install completed successfully, and retry if it seems stuck
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
  print_light_blue "Initial install failed or took too long. Retrying..."
  # Check for the stuck state and kill any hanging pnpm processes
  pkill -f pnpm
  sleep 10
  pnpm install | tee install.log
  INSTALL_STATUS=$?
  if [ $INSTALL_STATUS -ne 0 ]; then
    print_light_blue "The installation is still stuck after retry. Please check the logs for more details."
    exit 1
  fi
fi

# Copy the example .env file to .env
print_light_blue "Updating .env file..."
cp .env.example .env

# Replace environment variables with user input
print_light_blue "Updating .env with provided values..."
sed -i "s|CORS_ORIGIN_URL=.*|CORS_ORIGIN_URL=https://$CAD_DOMAIN|" .env
sed -i "s|NEXT_PUBLIC_PROD_ORIGIN=.*|NEXT_PUBLIC_PROD_ORIGIN=$CAD_API_URL|" .env
sed -i "s|DOMAIN=.*|DOMAIN=$CAD_DOMAIN|" .env



# NGINX configuration
print_light_blue "Configuring NGINX for $CAD_DOMAIN..."

cat > /etc/nginx/sites-available/$CAD_DOMAIN <<EOL
server {
    listen 80;
    server_name $CAD_DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}

server {
    listen 443 ssl;
    server_name $CAD_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$CAD_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$CAD_DOMAIN/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# Enable NGINX site configuration
ln -s /etc/nginx/sites-available/$CAD_DOMAIN /etc/nginx/sites-enabled/ &>/dev/null

# Test NGINX configuration
print_light_blue "Testing NGINX configuration..."
nginx -t &>/dev/null

# Reload NGINX
print_light_blue "Reloading NGINX..."
systemctl reload nginx &>/dev/null

# Certbot to get SSL certificate
print_light_blue "Getting SSL certificate from Certbot..."
certbot --nginx -d $CAD_DOMAIN &>/dev/null

# Build the site
print_light_blue "Building the site..."
pnpm build &>/dev/null

# Start a screen session
print_light_blue "Starting a screen session for the site..."
screen -dmS snailycad

# Start the site in the screen session
print_light_blue "Starting the site..."
screen -S snailycad -X stuff 'pnpm start\n'

# Success message
print_light_blue "Setup complete. Your CAD is now live at https://$CAD_DOMAIN."

# Final instruction
print_light_blue "To reattach to the screen session, run: screen -r snailycad"
