#!/bin/bash
set -e

echo "--- DeepStream Installation Script for Jetson Orin Nano ---"

echo "IMPORTANT: This script assumes you have already installed JetPack 6.2  on your Jetson Orin Nano."
echo "If you haven't, please do so using NVIDIA SDK Manager or by flashing the SD card image from:"
echo "https://developer.nvidia.com/embedded/jetpack"
echo ""

echo "--- Performing system update and upgrade ---"
sudo apt update
echo ""

echo "--- Ensuring ~/.local/bin is in PATH for current and future sessions ---"
# Check if the line already exists in .bashrc
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/.local/bin to PATH in ~/.bashrc"
else
    echo "~/.local/bin already found in PATH in ~/.bashrc. Skipping."
fi

export PATH="$HOME/.local/bin:$PATH"
echo "PATH for current script session updated to: $PATH"
echo ""


# --- Function to install or update GLib ---
install_glib() {
    echo "--- Checking and potentially updating GLib ---"

    # Get current GLib version
    CURRENT_GLIB_VERSION=$(pkg-config --modversion glib-2.0 2>/dev/null || echo "0.0.0")
    TARGET_GLIB_VERSION="2.76.6"

    echo "Current GLib version: ${CURRENT_GLIB_VERSION}"
    echo "Target GLib version: ${TARGET_GLIB_VERSION}"

    # Compare versions. Using awk for robust version comparison.
    # This logic checks if CURRENT_GLIB_VERSION is numerically less than TARGET_GLIB_VERSION
    if awk -v current="$CURRENT_GLIB_VERSION" -v target="$TARGET_GLIB_VERSION" 'BEGIN {
        if (current == "0.0.0") { print 1; exit; } # Force update if pkg-config failed
        split(current, c, ".");
        split(target, t, ".");
        for (i=1; i<=3; i++) {
            if (c[i] < t[i]) { print 1; exit; }
            if (c[i] > t[i]) { print 0; exit; }
        }
        print 0; # Versions are equal or current is greater
    }' | grep -q 1; then
        echo "GLib version is older than ${TARGET_GLIB_VERSION} or not found. Proceeding with update."

        sudo apt install -y python3-pip git build-essential
        sudo pip3 install meson ninja

        # Check if glib directory already exists to avoid cloning again if script is re-run
        if [ ! -d "glib" ]; then
            git clone https://github.com/GNOME/glib.git
        else
            echo "GLib source directory already exists. Attempting to update it."
            (cd glib && git pull)
        fi

        # Store current directory to return after glib operations
        local current_dir=$(pwd)
        cd glib

        git checkout "${TARGET_GLIB_VERSION}" # Checkout the specific version

        echo "Configuring and building GLib..."
        # Ensure build directory is clean if re-running
        if [ -d "build" ]; then
            rm -rf build
        fi
        meson build --prefix=/usr # Install to /usr
        ninja -C build/

        echo "Installing GLib..."
        cd build/
        sudo ninja install || { echo "ERROR: ninja install failed. Check error messages above."; exit 1; }
        sudo ldconfig # Update shared library cache

        echo "GLib update complete. New GLib version: $(pkg-config --modversion glib-2.0)"
        cd "$current_dir" # Go back to the original directory where the script was run from
    else
        echo "GLib is already at or newer than ${TARGET_GLIB_VERSION}. Skipping GLib update."
    fi
    echo ""
}

# --- Call the GLib installation function ---
install_glib

echo "--- Installing DeepStream Dependencies ---"
sudo apt update # Re-run update to ensure latest package lists
sudo apt install -y \
libssl3 \
libssl-dev \
libgstreamer1.0-0 \
gstreamer1.0-tools \
gstreamer1.0-plugins-good \
gstreamer1.0-plugins-bad \
gstreamer1.0-plugins-ugly \
gstreamer1.0-libav \
libgstreamer-plugins-base1.0-dev \
libgstrtspserver-1.0-0 \
libjansson4 \
libyaml-cpp-dev

echo "--- Installing librdkafka (for Kafka protocol adaptor) ---"
# Check if librdkafka directory already exists to avoid cloning again if script is re-run
if [ ! -d "librdkafka" ]; then
    git clone https://github.com/confluentinc/librdkafka.git
else
    echo "librdkafka source directory already exists. Attempting to update it."
    (cd librdkafka && git pull)
fi
# Store current directory to return after librdkafka operations
original_dir=$(pwd)
cd librdkafka
git checkout v2.2.0
./configure --enable-ssl
make
sudo make install
sudo ldconfig
cd "$original_dir" # Go back to the original directory

echo "--- Installing DeepStream SDK v7.1.0 ---"
# Define DeepStream tar package details
DEEPSTREAM_TAR="deepstream_sdk_v7.1.0_jetson.tbz2"
DOWNLOAD_URL="https://api.ngc.nvidia.com/v2/resources/nvidia/deepstream/versions/7.1/files/${DEEPSTREAM_TAR}"
DEEPSTREAM_INSTALL_DIR="/opt/nvidia/deepstream/deepstream-7.1"

# Check if DeepStream is already extracted to avoid re-extraction
if [ ! -d "$DEEPSTREAM_INSTALL_DIR" ]; then
    echo "Downloading DeepStream SDK from: ${DOWNLOAD_URL}"
    # Use -N (timestamping) or -nc (no clobber) to avoid re-downloading if already present
    wget --content-disposition "${DOWNLOAD_URL}" -O "${DEEPSTREAM_TAR}" || { echo "Failed to download DeepStream SDK."; exit 1; }

    echo "Extracting and installing DeepStream SDK..."
    sudo tar -xvf "${DEEPSTREAM_TAR}" -C / || { echo "Failed to extract DeepStream SDK."; exit 1; }
else
    echo "DeepStream SDK directory already exists at $DEEPSTREAM_INSTALL_DIR. Skipping extraction."
fi

# Navigate to the DeepStream installation directory and run install.sh
if [ -d "$DEEPSTREAM_INSTALL_DIR" ]; then
    cd "$DEEPSTREAM_INSTALL_DIR"
    sudo ./install.sh || { echo "Failed to run DeepStream install script."; exit 1; }
    sudo ldconfig
    cd - # Return to the previous directory (where the script was run from)
else
    echo "Error: DeepStream SDK installation directory not found at $DEEPSTREAM_INSTALL_DIR after extraction attempt."
    exit 1
fi

echo "--- Executing update_rtpmanager.sh ---"
# This script is part of the DeepStream installation, so it should be run after the SDK is installed.
if [ -f "${DEEPSTREAM_INSTALL_DIR}/update_rtpmanager.sh" ]; then
    sudo "${DEEPSTREAM_INSTALL_DIR}/update_rtpmanager.sh"
else
    echo "Warning: update_rtpmanager.sh not found at ${DEEPSTREAM_INSTALL_DIR}/. Please check your DeepStream installation path."
fi

# Copy librdkafka libraries to DeepStream lib directory
echo "--- Copying librdkafka libraries to DeepStream lib directory ---"
if [ -d "${DEEPSTREAM_INSTALL_DIR}/lib" ]; then
    sudo cp /usr/local/lib/librdkafka* "${DEEPSTREAM_INSTALL_DIR}/lib" || { echo "Failed to copy librdkafka libraries."; exit 1; }
    sudo ldconfig
else
    echo "Warning: DeepStream lib directory not found at ${DEEPSTREAM_INSTALL_DIR}/lib. Please check your DeepStream installation path."
fi


echo "--- DeepStream Installation Complete! ---"
echo "You can verify the installation by running:"
echo "deepstream-app --version"
echo "Or check the DeepStream documentation for sample applications."
