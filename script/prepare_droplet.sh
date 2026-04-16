#!/bin/bash
# Digital Ocean Droplet Preparation Script
# Run this script on a fresh Ubuntu droplet to prepare it for Kamal deployment

set -e

echo "================================================"
echo "Digital Ocean Droplet Preparation Script"
echo "================================================"

# Update system packages
echo "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install essential packages
echo "Installing essential packages..."
apt-get install -y \
  curl \
  wget \
  git \
  ufw \
  fail2ban \
  apt-transport-https \
  ca-certificates \
  software-properties-common

# Configure firewall
echo "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Configure fail2ban for SSH protection
echo "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Set up automatic security updates
echo "Setting up automatic security updates..."
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Create a swap file (helpful for small droplets)
echo "Creating swap file..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Set timezone
echo "Setting timezone to UTC..."
timedatectl set-timezone UTC

# Docker will be installed by Kamal, but we can pre-install it for faster setup
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo ""
echo "================================================"
echo "Server preparation complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Copy your SSH public key to this server:"
echo "   ssh-copy-id root@$(curl -s ifconfig.me)"
echo ""
echo "2. Update config/deploy.yml with this server's IP:"
echo "   $(curl -s ifconfig.me)"
echo ""
echo "3. Run 'bin/deploy setup' from your local machine"
echo ""

