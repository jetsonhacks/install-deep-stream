#!/bin/bash

# This script performs a multi-stage installation for Ultralytics and its ML dependencies
# on NVIDIA Jetson Orin with JetPack 6.2, strictly following the Ultralytics guide:
# https://docs.ultralytics.com/guides/nvidia-jetson/
#
# It handles the initial Ultralytics installation, reboots, and then automatically
# installs PyTorch, Torchvision, cuSPARSELt, and onnxruntime-gpu after the reboot.

# --- Configuration ---
# JetPack 6.2 typically uses Python 3.10.
PYTHON_VERSION="3.10"
PIP_EXEC="pip3" # Or "python3.10 -m pip" if you have multiple python3 versions

# PyTorch, Torchvision, and ONNX Runtime GPU versions explicitly from Ultralytics guide for JetPack 6.1
# Note: These are provided for JetPack 6.1 in the guide. Assuming compatibility with JetPack 6.2.
PYTORCH_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
TORCHVISION_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"
ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.20.0-cp310-cp310-linux_aarch64.whl"

# --- Script Flags and Paths ---
INSTALL_FLAG="/tmp/.ultralytics_post_reboot_install_in_progress"
POST_REBOOT_SCRIPT="/usr/local/bin/ultralytics_post_reboot_install.sh"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/ultralytics-post-reboot.service"

# --- Functions ---

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/ultralytics_install.log
}

# Function to perform post-reboot installations
post_reboot_install() {
    log_message "Starting post-reboot installation phase."

    # Remove the flag file to ensure this script runs only once
    if [ -f "$INSTALL_FLAG" ]; then
        rm "$INSTALL_FLAG"
        log_message "Removed installation flag: $INSTALL_FLAG"
    fi

    # Uninstall any incompatible torch/torchvision installed by default pip
    log_message "Attempting to uninstall potentially incompatible PyTorch and Torchvision..."
    $PIP_EXEC uninstall -y torch torchvision || log_message "No existing torch/torchvision found or failed to uninstall."

    # Install PyTorch
    log_message "Installing PyTorch from Ultralytics assets..."
    $PIP_EXEC install --no-cache-dir "$PYTORCH_WHL_URL" || { log_message "Failed to install PyTorch from Ultralytics assets."; exit 1; }
    log_message "PyTorch installed."

    # Install Torchvision
    log_message "Installing Torchvision from Ultralytics assets..."
    $PIP_EXEC install --no-cache-dir "$TORCHVISION_WHL_URL" || { log_message "Failed to install Torchvision from Ultralytics assets."; exit 1; }
    log_message "Torchvision installed."

    # Install cuSPARSELt
    log_message "Installing cuSPARSELt via apt..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring_1.1-1_all.deb || { log_message "Failed to download cuda-keyring.deb."; exit 1; }
    sudo dpkg -i /tmp/cuda-keyring_1.1-1_all.deb || { log_message "Failed to install cuda-keyring.deb."; exit 1; }
    sudo apt-get update || { log_message "Failed to update apt after adding keyring."; exit 1; }
    sudo apt-get -y install libcusparselt0 libcusparselt-dev || { log_message "Failed to install libcusparselt packages."; exit 1; }
    rm /tmp/cuda-keyring_1.1-1_all.deb
    log_message "cuSPARSELt installed."

    # Install onnxruntime-gpu
    log_message "Installing onnxruntime-gpu from Ultralytics assets..."
    $PIP_EXEC install --no-cache-dir "$ONNXRUNTIME_GPU_WHL_URL" || { log_message "Failed to install onnxruntime-gpu from Ultralytics assets."; exit 1; }
    log_message "ONNX Runtime GPU installed."

    # Reinstall numpy to version 1.23.5 to fix potential issues
    log_message "Reinstalling numpy to version 1.23.5 as recommended by Ultralytics guide..."
    $PIP_EXEC install numpy==1.23.5 --prefer-binary || { log_message "Failed to reinstall numpy==1.23.5. Continuing but be aware of numpy issues."; }
    log_message "Numpy set to 1.23.5."

    log_message "All post-reboot ML dependencies installed successfully."

    # Disable and remove the systemd service after successful execution
    log_message "Cleaning up systemd service for post-reboot script."
    sudo systemctl disable ultralytics-post-reboot.service || log_message "Failed to disable systemd service."
    sudo rm "$SYSTEMD_SERVICE_FILE" || log_message "Failed to remove systemd service file."
    sudo rm "$POST_REBOOT_SCRIPT" || log_message "Failed to remove post-reboot script."
    sudo systemctl daemon-reload || log_message "Failed to reload systemd daemon."
    log_message "Cleanup complete."
}

# --- Main Script Logic ---

# Check if the post-reboot flag exists, if so, execute the post-reboot installation
if [ -f "$INSTALL_FLAG" ]; then
    post_reboot_install
    exit 0 # Exit after post-reboot installation
fi

# --- Initial Installation Phase (Runs before first reboot) ---
log_message "Starting initial Ultralytics installation phase."

# Ensure script is run as root for apt commands
if [ "$(id -u)" -ne 0 ]; then
    log_message "This script needs to be run with sudo. Re-running with sudo..."
    exec sudo bash "$0" "$@"
    exit $?
fi

# Set bash to exit on error
set -e

# Create a log file (if not already created by post-reboot phase on a previous failed run)
touch /var/log/ultralytics_install.log
chmod 666 /var/log/ultralytics_install.log # Make it world-writable for easier debugging if needed

# Step 1: Update package list, install pip, and upgrade to latest
log_message "Step 1: Updating package list, installing/upgrading pip..."
apt update -y
apt install -y python3-pip
$PIP_EXEC install -U pip

# Step 2: Install ultralytics pip package with optional dependencies
log_message "Step 2: Installing ultralytics pip package with export dependencies..."
$PIP_EXEC install ultralytics[export]

# Create the post-reboot script
log_message "Creating post-reboot script at $POST_REBOOT_SCRIPT..."
# Using 'EOF_SCRIPT' with quotes to prevent variable expansion now, let the script itself handle it.
cat << 'EOF_SCRIPT' | sudo tee "$POST_REBOOT_SCRIPT" > /dev/null
#!/bin/bash
# This script is automatically generated and executed once after reboot.
# It installs PyTorch, Torchvision, cuSPARSELt, and onnxruntime-gpu.

# Ensure logging to a file
exec > >(tee -a /var/log/ultralytics_install.log) 2>&1

# Define variables consistent with the main script
PYTHON_VERSION="3.10"
PIP_EXEC="pip3"

# PyTorch, Torchvision, and ONNX Runtime GPU versions explicitly from Ultralytics guide for JetPack 6.1
# Note: These are provided for JetPack 6.1 in the guide. Assuming compatibility with JetPack 6.2.
PYTORCH_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
TORCHVISION_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"
ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.20.0-cp310-cp310-linux_aarch64.whl"

INSTALL_FLAG="/tmp/.ultralytics_post_reboot_install_in_progress"
POST_REBOOT_SCRIPT="/usr/local/bin/ultralytics_post_reboot_install.sh"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/ultralytics-post-reboot.service"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Set bash to exit on error
set -e

log_message "Starting post-reboot installation phase."

# Remove the flag file to ensure this script runs only once
if [ -f "$INSTALL_FLAG" ]; then
    rm "$INSTALL_FLAG"
    log_message "Removed installation flag: $INSTALL_FLAG"
fi

# Uninstall any incompatible torch/torchvision installed by default pip
log_message "Attempting to uninstall potentially incompatible PyTorch and Torchvision..."
$PIP_EXEC uninstall -y torch torchvision || log_message "No existing torch/torchvision found or failed to uninstall."

# Install PyTorch
log_message "Installing PyTorch from Ultralytics assets..."
$PIP_EXEC install --no-cache-dir "$PYTORCH_WHL_URL" || { log_message "Failed to install PyTorch from Ultralytics assets."; exit 1; }
log_message "PyTorch installed."

# Install Torchvision
log_message "Installing Torchvision from Ultralytics assets..."
$PIP_EXEC install --no-cache-dir "$TORCHVISION_WHL_URL" || { log_message "Failed to install Torchvision from Ultralytics assets."; exit 1; }
log_message "Torchvision installed."

# Install cuSPARSELt
log_message "Installing cuSPARSELt via apt..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring_1.1-1_all.deb || { log_message "Failed to download cuda-keyring.deb."; exit 1; }
sudo dpkg -i /tmp/cuda-keyring_1.1-1_all.deb || { log_message "Failed to install cuda-keyring.deb."; exit 1; }
sudo apt-get update || { log_message "Failed to update apt after adding keyring."; exit 1; }
sudo apt-get -y install libcusparselt0 libcusparselt-dev || { log_message "Failed to install libcusparselt packages."; exit 1; }
rm /tmp/cuda-keyring_1.1-1_all.deb
log_message "cuSPARSELt installed."

# Install onnxruntime-gpu
log_message "Installing onnxruntime-gpu from Ultralytics assets..."
$PIP_EXEC install --no-cache-dir "$ONNXRUNTIME_GPU_WHL_URL" || { log_message "Failed to install onnxruntime-gpu from Ultralytics assets."; exit 1; }
log_message "ONNX Runtime GPU installed."

# Reinstall numpy to version 1.23.5 to fix potential issues
log_message "Reinstalling numpy to version 1.23.5 as recommended by Ultralytics guide..."
$PIP_EXEC install numpy==1.23.5 --prefer-binary || { log_message "Failed to reinstall numpy==1.23.5. Continuing but be aware of numpy issues."; }
log_message "Numpy set to 1.23.5."

log_message "All post-reboot ML dependencies installed successfully."

# Disable and remove the systemd service after successful execution
log_message "Cleaning up systemd service for post-reboot script."
systemctl disable ultralytics-post-reboot.service || log_message "Failed to disable systemd service."
rm "$SYSTEMD_SERVICE_FILE" || log_message "Failed to remove systemd service file."
rm "$POST_REBOOT_SCRIPT" || log_message "Failed to remove post-reboot script."
systemctl daemon-reload || log_message "Failed to reload systemd daemon."
log_message "Cleanup complete."

EOF_SCRIPT
chmod +x "$POST_REBOOT_SCRIPT"
log_message "Post-reboot script created and made executable."

# Create the systemd service file
log_message "Creating systemd service file at $SYSTEMD_SERVICE_FILE..."
cat << EOF | sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null
[Unit]
Description=Ultralytics Post-Reboot Install Script
After=network-online.target multi-user.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$POST_REBOOT_SCRIPT
RemainAfterExit=true
# Ensure script runs as root
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SYSTEMD_SERVICE_FILE"
log_message "Systemd service file created."

# Enable the systemd service
log_message "Enabling systemd service 'ultralytics-post-reboot.service'..."
systemctl daemon-reload
systemctl enable ultralytics-post-reboot.service
log_message "Systemd service enabled. It will run on next reboot."

# Create the flag file
log_message "Creating installation flag file: $INSTALL_FLAG"
touch "$INSTALL_FLAG"
chmod 666 "$INSTALL_FLAG" # Make it world-writable for easier debugging if needed

log_message "Initial installation phase complete. Rebooting device to continue with ML stack installation."
log_message "Monitor /var/log/ultralytics_install.log after reboot for progress of the second stage."

# Step 3: Reboot the device
reboot
