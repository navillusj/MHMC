#!/bin/bash

# --- VARIABLES ---
# You can change these variables if you need to
USB_DEV="/dev/sda1"
MOUNT_POINT="/mnt/media-drive"
NETWORK_INTERFACE="eth0"

# --- START OF SCRIPT ---
echo "Starting automated media server setup..."

# Prompt for Transmission credentials
read -p "Enter a username for Transmission: " TRANSMISSION_USER
read -s -p "Enter a password for Transmission: " TRANSMISSION_PASS
echo

# Prompt for media directory, with option for root
read -p "Enter the directory on the USB drive for media (e.g., 'downloads') or press Enter for the root directory: " MEDIA_DIR

# Determine the media path based on user input
if [ -z "$MEDIA_DIR" ]; then
    MEDIA_PATH="$MOUNT_POINT"
else
    MEDIA_PATH="$MOUNT_POINT/$MEDIA_DIR"
fi

# Prompt for cleanup schedule
echo ""
echo "Select a cleanup schedule for the USB drive to prevent it from getting full:"
echo "1: Every 30 days"
echo "2: Every 60 days"
echo "3: Every 90 days"
echo "4: Off (I'll clean it myself)"
read -p "Enter your choice (1, 2, 3, or 4): " CLEANUP_CHOICE

# 1. Update and Upgrade System
echo "1. Updating and upgrading the system..."
sudo apt update -y
sudo apt upgrade -y

# 2. Format and Auto-mount USB Drive
echo "2. Formatting and configuring USB drive for auto-mounting..."
sudo umount $USB_DEV > /dev/null 2>&1
sudo mkfs.ext4 -F $USB_DEV
sudo mkdir -p $MOUNT_POINT
UUID=$(sudo blkid -s UUID -o value $USB_DEV)
echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
sudo chown -R $USER:$USER $MOUNT_POINT

# 3. Create a shared 'media' group
echo "3. Creating shared 'media' group and adding users..."
sudo addgroup media
sudo usermod -a -G media debian-transmission
sudo usermod -a -G media minidlna

# 4. Install Transmission
echo "4. Installing Transmission..."
sudo apt install transmission-daemon -y
sudo systemctl stop transmission-daemon

# 5. Configure Transmission
echo "5. Configuring Transmission..."
sudo mkdir -p "$MEDIA_PATH"
# Set permissions and ownership for the media folder
sudo chown -R $USER:media "$MEDIA_PATH"
sudo chmod -R 775 "$MEDIA_PATH"
# Update the Transmission configuration file
sudo sed -i "s|.*\"rpc-password\".*|\"rpc-password\": \"$TRANSMISSION_PASS\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-username\".*|\"rpc-username\": \"$TRANSMISSION_USER\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-whitelist-enabled\".*|\"rpc-whitelist-enabled\": false,|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"download-dir\".*|\"download-dir\": \"$MEDIA_PATH\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir\".*|\"incomplete-dir\": \"$MEDIA_PATH\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir-enabled\".*|\"incomplete-dir-enabled\": true,|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir\".*|\"watch-dir\": \"$MEDIA_PATH\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir-enabled\".*|\"watch-dir-enabled\": true,|" /etc/transmission-daemon/settings.json
sudo systemctl start transmission-daemon
sudo systemctl enable transmission-daemon

# 6. Install MiniDLNA
echo "6. Installing MiniDLNA..."
sudo apt install minidlna -y
sudo systemctl stop minidlna

# 7. Configure MiniDLNA
echo "7. Configuring MiniDLNA..."
sudo cp /etc/minidlna.conf /etc/minidlna.conf.bak
sudo sed -i '/^media_dir=/d' /etc/minidlna.conf
# Configure for Pictures, Audio, and Video files, and map to the media path
sudo sed -i "/^#media_dir=/a media_dir=V,P,A,$MEDIA_PATH" /etc/minidlna.conf
sudo sed -i "/^#friendly_name=/a friendly_name=Home Media Server" /etc/minidlna.conf
sudo sed -i "s/#user=minidlna/user=minidlna/" /etc/minidlna.conf
sudo chown -R minidlna:minidlna /var/cache/minidlna
sudo systemctl start minidlna
sudo systemctl enable minidlna

# 8. Install and Configure Lighttpd
echo "8. Installing and configuring Lighttpd..."
sudo apt install lighttpd -y
if [ -f "index.html" ]; then
    sudo mv index.html /var/www/html/
else
    echo "Warning: index.html not found in the same directory as the script. Please ensure it is there."
fi
sudo rm /var/www/html/index.lighttpd.html
DEVICE_IP=$(hostname -I | awk '{print $1}')
sudo sed -i "s|<your_pi_ip>|$DEVICE_IP|" /var/www/html/index.html
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/
sudo systemctl restart lighttpd

# 9. Configure cleanup job
echo "9. Configuring cleanup job..."
(sudo crontab -l | grep -v 'find $MEDIA_PATH' || true) | sudo crontab -
if [ "$CLEANUP_CHOICE" == "1" ]; then
    CLEANUP_SCHEDULE="0 2 * */1 *"
    echo "Cleanup scheduled for every 30 days."
elif [ "$CLEANUP_CHOICE" == "2" ]; then
    CLEANUP_SCHEDULE="0 2 * */2 *"
    echo "Cleanup scheduled for every 60 days."
elif [ "$CLEANUP_CHOICE" == "3" ]; then
    CLEANUP_SCHEDULE="0 2 * */3 *"
    echo "Cleanup scheduled for every 90 days."
fi

if [ "$CLEANUP_CHOICE" != "4" ]; then
    CLEANUP_COMMAND="find \"$MEDIA_PATH\" -mindepth 1 -delete"
    (sudo crontab -l 2>/dev/null; echo "$CLEANUP_SCHEDULE $CLEANUP_COMMAND") | sudo crontab -
    echo "Cleanup cron job added successfully."
else
    echo "Automatic cleanup disabled."
fi

# 10. Add daily reboot and MiniDLNA rescan schedules
echo "10. Adding daily reboot and MiniDLNA rescan schedules..."
# Remove any existing reboot or minidlna cron jobs to prevent duplicates
(sudo crontab -l | grep -v 'minidlnad -R' || true) | sudo crontab -
(sudo crontab -l | grep -v 'shutdown -r now' || true) | sudo crontab -
# Add the cron job to rescan MiniDLNA every 30 minutes
(sudo crontab -l 2>/dev/null; echo "*/30 * * * * /usr/bin/minidlnad -R") | sudo crontab -
# Add the cron job to reboot every day at midnight (00:00)
(sudo crontab -l 2>/dev/null; echo "0 0 * * * /sbin/shutdown -r now") | sudo crontab -
echo "Automatic reboot scheduled for every night at midnight."

# 11. Configure firewall for remote access (UFW)
echo "11. Configuring firewall for remote access..."
sudo apt install ufw -y
sudo ufw allow 9091/tcp
sudo ufw allow 8200/tcp
sudo ufw allow 80/tcp
sudo ufw enable

# Final message
echo "--- Setup Complete! ---"
echo "You can now access your home page at http://$DEVICE_IP"
echo "Transmission's web interface is at http://$DEVICE_IP:9091"
echo "Username: $TRANSMISSION_USER"
echo "Password: (hidden)"
echo ""
echo "Your MiniDLNA server 'Home Media Server' should be discoverable on your network."
echo "Your device will now reboot every night at midnight to ensure all services are operating normally."
