#!/bin/bash

# --- VARIABLES ---
# You can change these variables if you need to
# The UUID of your USB drive can be found using the 'lsblk -f' command
# This script will format the first USB drive it finds, be careful!
USB_DEV="/dev/sda1"
MOUNT_POINT="/mnt/media-drive"
NETWORK_INTERFACE="eth0" # Change this to your network interface if it's different

# --- START OF SCRIPT ---
echo "Starting automated media server setup..."

# Prompt for Transmission credentials
read -p "Enter a username for Transmission: " TRANSMISSION_USER
read -s -p "Enter a password for Transmission: " TRANSMISSION_PASS
echo

# 1. Update and Upgrade System
echo "1. Updating and upgrading the system..."
sudo apt update -y
sudo apt upgrade -y

# 2. Format and Auto-mount USB Drive
echo "2. Formatting and configuring USB drive for auto-mounting..."
# Unmount the device if it's already mounted
sudo umount $USB_DEV > /dev/null 2>&1
# Format the USB drive with ext4 filesystem
sudo mkfs.ext4 -F $USB_DEV
# Create the mount point directory
sudo mkdir -p $MOUNT_POINT
# Get the UUID of the USB device
UUID=$(sudo blkid -s UUID -o value $USB_DEV)
# Add an entry to fstab for auto-mounting
echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
# Mount the drive
sudo mount -a
# Set correct permissions
sudo chown -R $USER:$USER $MOUNT_POINT

# 3. Install Transmission
echo "3. Installing Transmission..."
sudo apt install transmission-daemon -y
# Stop the service to configure it
sudo systemctl stop transmission-daemon

# 4. Configure Transmission
echo "4. Configuring Transmission..."
# Create necessary directories for Transmission
sudo mkdir -p $MOUNT_POINT/downloads
# Update the Transmission configuration file
sudo sed -i "s|.*\"rpc-password\".*|\"rpc-password\": \"$TRANSMISSION_PASS\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-username\".*|\"rpc-username\": \"$TRANSMISSION_USER\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-whitelist-enabled\".*|\"rpc-whitelist-enabled\": false,|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"download-dir\".*|\"download-dir\": \"$MOUNT_POINT/downloads\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir\".*|\"incomplete-dir\": \"$MOUNT_POINT/downloads\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir-enabled\".*|\"incomplete-dir-enabled\": true,|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir\".*|\"watch-dir\": \"$MOUNT_POINT/downloads/watch\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir-enabled\".*|\"watch-dir-enabled\": true,|" /etc/transmission-daemon/settings.json
# Change ownership of Transmission's config and directories
sudo chown -R debian-transmission:debian-transmission /etc/transmission-daemon/
sudo chown -R debian-transmission:debian-transmission $MOUNT_POINT/downloads

# Restart Transmission service
sudo systemctl start transmission-daemon
sudo systemctl enable transmission-daemon

# 5. Install MiniDLNA
echo "5. Installing MiniDLNA..."
sudo apt install minidlna -y
# Stop the service to configure it
sudo systemctl stop minidlna

# 6. Configure MiniDLNA
echo "6. Configuring MiniDLNA..."
# Backup original config
sudo cp /etc/minidlna.conf /etc/minidlna.conf.bak
# Remove the existing media_dir lines to avoid conflicts
sudo sed -i '/^media_dir=/d' /etc/minidlna.conf
# Add new media_dir lines pointing to the mounted USB drive
sudo sed -i "/^#media_dir=/a media_dir=V,$MOUNT_POINT/downloads" /etc/minidlna.conf
sudo sed -i "/^#friendly_name=/a friendly_name=Home Media Server" /etc/minidlna.conf
# Change the user to run as minidlna
sudo sed -i "s/#user=minidlna/user=minidlna/" /etc/minidlna.conf
# Change ownership of the directories
sudo chown -R minidlna:minidlna $MOUNT_POINT/downloads

# Restart MiniDLNA service
sudo systemctl start minidlna
sudo systemctl enable minidlna

# 7. Install and Configure Lighttpd
echo "7. Installing and configuring Lighttpd..."
sudo apt install lighttpd -y
# Create web root directory
sudo mkdir -p /var/www/html/media-center
# Move index.html into the new directory
if [ -f "index.html" ]; then
    sudo mv index.html /var/www/html/media-center/
else
    echo "Warning: index.html not found in the same directory as the script. Please ensure it is there."
fi
# Get the IP address of the device
DEVICE_IP=$(hostname -I | awk '{print $1}')
# Replace the placeholder IP in index.html with the actual IP
sudo sed -i "s|<your_pi_ip>|$DEVICE_IP|" /var/www/html/media-center/index.html
# Configure Lighttpd to serve the new directory
sudo sed -i "s|server.document-root = \"/var/www/html\"|server.document-root = \"/var/www/html/media-center\"|" /etc/lighttpd/lighttpd.conf
# Restart Lighttpd
sudo systemctl restart lighttpd

# 8. Configure firewall for remote access (UFW)
echo "8. Configuring firewall for remote access..."
sudo apt install ufw -y
sudo ufw allow 9091/tcp # Transmission RPC port
sudo ufw allow 8200/tcp # MiniDLNA port
sudo ufw allow 80/tcp # Lighttpd web server port
sudo ufw enable
echo "Firewall is now configured and enabled. You may need to manually enable it if you have a different firewall."

# Final message
echo "--- Setup Complete! ---"
echo "You can now access your home page at http://$DEVICE_IP"
echo "Transmission's web interface is at http://$DEVICE_IP:9091"
echo "Username: $TRANSMISSION_USER"
echo "Password: (hidden)"
echo ""
echo "Your MiniDLNA server 'Home Media Server' should be discoverable on your network."
echo "Remember to change the default Transmission username and password for security!"
