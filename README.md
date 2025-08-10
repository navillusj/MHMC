# Universal Media Center Setup Script

<img width="512" height="395" alt="image" src="https://github.com/user-attachments/assets/3e031ff4-c6d8-4286-b639-80fd59a3e0ef" />

This repository contains a simple, universal `install.sh` script to transform a single-board computer (SBC) like a Raspberry Pi or Rock 4C Plus into a powerful mini home media center. It automates the installation and configuration of essential services, making the setup process fast and straightforward.

***

### Features

* **Auto-Mount USB:** Automatically formats a connected USB drive with the `ext4` filesystem and configures it to mount on startup.
* **Transmission:** Installs the Transmission BitTorrent client and configures it to use the mounted USB drive for downloads.
* **MiniDLNA:** Installs MiniDLNA to act as a media server, allowing you to stream content from your USB drive to DLNA-compatible devices on your network (e.g., smart TVs, gaming consoles).
* **Web Interface:** Sets up a Lighttpd web server with a custom HTML home page that provides quick links to Transmission and MiniDLNA.
* **Firewall Configuration:** Configures the `ufw` firewall to allow access to all necessary services.

***

### Prerequisites

* A single-board computer (SBC) with a **Debian-based OS** installed (e.g., Raspberry Pi OS, Armbian, Ubuntu Server).
* A USB drive that you are willing to **format**. The script will erase all data on the drive.
* An internet connection for your SBC.
* **The `install.sh` and `index.html` files must be in the same directory.**

***

### Installation

Follow these steps to set up your media center.

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/navillusj/MHMC.git](https://github.com/navillusj/MHMC.git)
    cd MHMC
    ```
2.  **Make the Script Executable:**
    ```bash
    chmod +x install.sh
    ```
3.  **Run the Script:**
    Run the script with `sudo` to ensure it has the necessary permissions. You will be prompted to create a username and password for the Transmission web interface.
    ```bash
    sudo ./install.sh
    ```
    The script will print progress updates and a final message once the setup is complete.

***

### Configuration

Before running the script, you can edit the variables at the top of the `install.sh` file to fit your specific needs:

* **`USB_DEV`**: This is the device name of your USB drive (e.g., `/dev/sda1`). You can find this by running the `lsblk -f` command.
* **`MOUNT_POINT`**: The directory where your USB drive will be mounted.
* **`NETWORK_INTERFACE`**: The name of your network interface (e.g., `eth0`).

***

### Usage

Once the script has finished, you can access your services:

* **Home Page:** Navigate to `http://<your_device_ip>` in your web browser.
* **Transmission Web UI:** Access the BitTorrent client at `http://<your_device_ip>:9091`.
* **MiniDLNA:** Your media server will be discoverable on your network with the name **"Home Media Server."** You can access it from any DLNA-compatible device.

**⚠️ Security Notice:** After installation, it's highly recommended to log into the Transmission web interface and change the password for added security.
