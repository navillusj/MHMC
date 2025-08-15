#!/bin/bash

# --- VARIABLES ---
# You can change these variables if you need to
USB_DEV="/dev/sda1"
MOUNT_POINT="/mnt/media-drive"
NETWORK_INTERFACE="eth0"

# --- FUNCTIONS ---
# This function checks if a package is installed and installs it if it's not.
install_if_not_found() {
    PACKAGE=$1
    echo "Checking for package: $PACKAGE..."
    if dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        echo "$PACKAGE is already installed. Skipping."
    else
        echo "$PACKAGE is not installed. Installing..."
        sudo apt install -y "$PACKAGE"
    fi
}

# --- START OF SCRIPT ---
echo "Starting automated media server setup..."

## 1. Update and Upgrade System
echo "1. Updating and upgrading the system..."
sudo apt update -y
sudo apt upgrade -y

## 2. Install all necessary dependencies
echo "2. Installing necessary dependencies..."
install_if_not_found "cron"
install_if_not_found "transmission-daemon"
install_if_not_found "minidlna"
install_if_not_found "lighttpd"
install_if_not_found "ufw"

## 3. Detect and Mount USB
echo "3. Formatting and configuring USB drive for auto-mounting..."
sudo umount $USB_DEV > /dev/null 2>&1
sudo mkfs.ext4 -F $USB_DEV
sudo mkdir -p $MOUNT_POINT
UUID=$(sudo blkid -s UUID -o value $USB_DEV)
echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
sudo chown -R $USER:$USER $MOUNT_POINT

## 4. Set Transmission remote username and password
echo "4. Setting Transmission remote username and password..."
sudo systemctl stop transmission-daemon
read -p "Enter a username for Transmission: " TRANSMISSION_USER
read -s -p "Enter a password for Transmission: " TRANSMISSION_PASS
echo
sudo sed -i "s|.*\"rpc-password\".*|\"rpc-password\": \"$TRANSMISSION_PASS\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-username\".*|\"rpc-username\": \"$TRANSMISSION_USER\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"rpc-whitelist-enabled\".*|\"rpc-whitelist-enabled\": false,|" /etc/transmission-daemon/settings.json

## 5. Set Transmission location to root of mounted USB
echo "5. Setting Transmission location to the root of the mounted USB..."
sudo sed -i "s|.*\"download-dir\".*|\"download-dir\": \"$MOUNT_POINT\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir\".*|\"incomplete-dir\": \"$MOUNT_POINT\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"incomplete-dir-enabled\".*|\"incomplete-dir-enabled\": true,|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir\".*|\"watch-dir\": \"$MOUNT_POINT\",|" /etc/transmission-daemon/settings.json
sudo sed -i "s|.*\"watch-dir-enabled\".*|\"watch-dir-enabled\": true,|" /etc/transmission-daemon/settings.json

## 6. Set MiniDLNA location to the root of the mounted USB
echo "6. Setting MiniDLNA location to the root of the mounted USB for P/V/A files..."
sudo systemctl stop minidlna
sudo cp /etc/minidlna.conf /etc/minidlna.conf.bak
sudo sed -i '/^media_dir=/d' /etc/minidlna.conf
# Configure for Pictures, Audio, and Video files, and map to the media path
sudo sed -i "/^#media_dir=/a media_dir=V,P,A,$MOUNT_POINT" /etc/minidlna.conf
sudo sed -i "/^#friendly_name=/a friendly_name=Home Media Server" /etc/minidlna.conf
sudo sed -i "s/#user=minidlna/user=minidlna/" /etc/minidlna.conf

## 7. Update permissions so MiniDLNA and Transmission have access to Read & Write
echo "7. Updating permissions for MiniDLNA and Transmission..."
sudo addgroup media
sudo usermod -a -G media debian-transmission
sudo usermod -a -G media minidlna
sudo chown -R $USER:media "$MOUNT_POINT"
sudo chmod -R 775 "$MOUNT_POINT"

# Restart services
echo "Restarting services with new configurations..."
sudo systemctl start transmission-daemon
sudo systemctl enable transmission-daemon
sudo chown -R minidlna:minidlna /var/cache/minidlna
sudo systemctl start minidlna
sudo systemctl enable minidlna

## 8. Add cleanup schedule
echo "8. Adding cleanup schedule..."
echo ""
echo "Select a cleanup schedule for the USB drive to prevent it from getting full:"
echo "1: Every 30 days"
echo "2: Every 60 days"
echo "3: Every 90 days"
echo "4: Off (I'll clean it myself)"
read -p "Enter your choice (1, 2, 3, or 4): " CLEANUP_CHOICE
(sudo crontab -l | grep -v 'find $MOUNT_POINT' || true) | sudo crontab -
if [ "$CLEANUP_CHOICE" == "1" ]; then
    CLEANUP_SCHEDULE="0 2 * */1 *"
    CLEANUP_COMMAND="find \"$MOUNT_POINT\" -mindepth 1 -delete"
    (sudo crontab -l 2>/dev/null; echo "$CLEANUP_SCHEDULE $CLEANUP_COMMAND") | sudo crontab -
elif [ "$CLEANUP_CHOICE" == "2" ]; then
    CLEANUP_SCHEDULE="0 2 * */2 *"
    CLEANUP_COMMAND="find \"$MOUNT_POINT\" -mindepth 1 -delete"
    (sudo crontab -l 2>/dev/null; echo "$CLEANUP_SCHEDULE $CLEANUP_COMMAND") | sudo crontab -
elif [ "$CLEANUP_CHOICE" == "3" ]; then
    CLEANUP_SCHEDULE="0 2 * */3 *"
    CLEANUP_COMMAND="find \"$MOUNT_POINT\" -mindepth 1 -delete"
    (sudo crontab -l 2>/dev/null; echo "$CLEANUP_SCHEDULE $CLEANUP_COMMAND") | sudo crontab -
else
    echo "Automatic cleanup disabled."
fi

## 9. Add auto reboot nightly
echo "9. Adding nightly reboot and MiniDLNA rescan schedules..."
(sudo crontab -l | grep -v 'minidlnad -R' || true) | sudo crontab -
(sudo crontab -l | grep -v 'shutdown -r now' || true) | sudo crontab -
(sudo crontab -l 2>/dev/null; echo "*/30 * * * * /usr/bin/minidlnad -R") | sudo crontab -
(sudo crontab -l 2>/dev/null; echo "0 0 * * * /sbin/shutdown -r now") | sudo crontab -

## 10. Install and Configure Lighttpd
echo "10. Installing and configuring Lighttpd..."
if [ -f "index.html" ]; then
    sudo mv index.html /var/www/html/
    sudo rm /var/www/html/index.lighttpd.html
    DEVICE_IP=$(hostname -I | awk '{print $1}')
    sudo sed -i "s|<your_pi_ip>|$DEVICE_IP|" /var/www/html/index.html
    sudo chown -R www-data:www-data /var/www/html/
    sudo chmod -R 755 /var/www/html/
    sudo systemctl restart lighttpd
else
    echo "Warning: index.html not found, skipping Lighttpd configuration."
fi

## 11. Configure firewall for remote access (UFW)
echo "11. Configuring firewall for remote access..."
install_if_not_found "ufw"
sudo ufw allow 9091/tcp
sudo ufw allow 8200/tcp
sudo ufw allow 80/tcp
sudo ufw enable
