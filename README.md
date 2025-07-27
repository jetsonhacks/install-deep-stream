# install-deep-stream
Install Deepstream on Jetson Orin Developer Kits

# WIP
This shell script automates the installation of NVIDIA DeepStream SDK 7.1 on a Jetson Orin device. It handles essential prerequisites, including common dependencies, a proactive fix for a known GLib issue (updating to version 2.76.6), and the installation of librdkafka for Kafka protocol support. Finally, it downloads and installs the DeepStream SDK from the NGC Catalog. Taken from: https://docs.nvidia.com/metropolis/deepstream/dev-guide/text/DS_Installation.html

Key Features:

* Automates dependency installation.
* Includes a version check and update for GLib to mitigate common runtime errors.
* Installs librdkafka for messaging capabilities.
* Downloads and extracts DeepStream SDK 7.1 directly to the system.

### Prerequisites:

* JetPack 6.2 GA (L4T 36.4) must be pre-installed on your Jetson Orin. This script does not flash your device; JetPack must be installed separately using NVIDIA SDK Manager or the appropriate SD card image.
* An active internet connection.

### Usage:

Ensure JetPack 6.2 GA is installed on your Jetson Orin Nano.

Download or copy the install-deepstream.sh script to your Jetson device.

Make the script executable:

```
chmod +x install-deepstream.sh
```
Run the script:

```
./install-deepstream.sh
```

The script will prompt for sudo password as needed.

Upon successful completion, DeepStream 7.1 will be installed, and you can verify the installation by running deepstream-app --version or exploring the DeepStream sample applications.

## Releases
### July, 2025
* Initial Release
