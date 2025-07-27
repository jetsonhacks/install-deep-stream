#!/bin/bash
set -e

echo "--- DeepStream Installation Script for Jetson Orin Nano (APT Version) ---"

echo "IMPORTANT: This script assumes you have already installed JetPack 6.1 GA on your Jetson Orin Nano."
echo "If you haven't, please do so using NVIDIA SDK Manager or by flashing the SD card image from:"
echo "https://developer.nvidia.com/embedded/jetpack"
echo ""

echo "--- Performing system update and upgrade ---"
sudo apt update
sudo apt upgrade -y
echo ""

echo "--- Ensuring ~/.local/bin is in PATH ---"
# This part adds/ensures ~/.local/bin is in ~/.bashrc for future *interactive* sessions.
# This is a persistent change for the user's login environment.
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/.local/bin to PATH in ~/.bashrc for future sessions."
else
    echo "~/.local/bin already found in PATH in ~/.bashrc. Skipping permanent addition."
fi

# --- IMPORTANT: Directly modify PATH for the current script session. ---
# This ensures that any executables installed into ~/.local/bin/ are immediately discoverable.
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

    if awk -v current="$CURRENT_GLIB_VERSION" -v target="$TARGET_GLIB_VERSION" 'BEGIN {
        if (current == "0.0.0") { print 1; exit; }
        split(current, c, ".");
        split(target, t, ".");
        for (i=1; i<=3; i++) {
            if (c[i] < t[i]) { print 1; exit; }
            if (c[i] > t[i]) { print 0; exit; }
        }
        print 0;
    }' | grep -q 1; then
        echo "GLib version is older than ${TARGET_GLIB_VERSION} or not found. Proceeding with update."

        sudo apt install -y python3-pip git build-essential

        echo "Installing meson and ninja system-wide via sudo pip3..."
        sudo pip3 install meson ninja || { echo "ERROR: Failed to install meson/ninja via sudo pip3. Please check pip3, network, and permissions."; exit 1; }

        # Verify that meson and ninja are now discoverable system-wide
        echo "Verifying 'meson' and 'ninja' are now discoverable system-wide:"
        if ! which meson > /dev/null; then
            echo "ERROR: 'meson' command not found in system PATH. This is unexpected after sudo pip3 install."
            exit 1
        fi
        if ! which ninja > /dev/null; then
            echo "ERROR: 'ninja' command not found in system PATH. This is unexpected after sudo pip3 install."
            exit 1
        fi
        echo "Meson and Ninja are now discoverable in the system PATH."


        # Check if glib directory already exists to avoid cloning again if script is re-run
        if [ ! -d "glib" ]; then
            git clone https://github.com/GNOME/glib.git || { echo "ERROR: Failed to clone GLib repository."; exit 1; }
        else
            echo "GLib source directory already exists. Ensuring correct version and a clean state."
            local current_glib_dir=$(pwd)
            cd glib

            git fetch origin || { echo "ERROR: Failed to fetch GLib updates."; exit 1; }
            git clean -dfx || { echo "Warning: Failed to git clean GLib repository."; }
            cd "$current_glib_dir"
        fi

        local current_dir=$(pwd)
        cd glib

        echo "Checking out GLib version ${TARGET_GLIB_VERSION}..."
        git checkout "${TARGET_GLIB_VERSION}" || { echo "ERROR: Failed to checkout GLib version ${TARGET_GLIB_VERSION}."; exit 1; }

        echo "Configuring and building GLib..."
        if [ -d "build" ]; then
            rm -rf build
        fi
        meson build --prefix=/usr || { echo "ERROR: meson build failed. Check error messages above."; exit 1; }
        ninja -C build/ || { echo "ERROR: ninja build failed. Check error messages above."; exit 1; }

        echo "Installing GLib..."
        cd build/
        sudo ninja install || { echo "ERROR: ninja install failed. Check error messages above."; exit 1; }
        sudo ldconfig

        echo "GLib update complete. New GLib version: $(pkg-config --modversion glib-2.0)"
        cd "$current_dir"
    else
        echo "GLib is already at or newer than ${TARGET_GLIB_VERSION}. Skipping GLib update."
    fi
    echo ""
}


# --- Call the GLib installation function ---
install_glib

echo "--- Installing Core DeepStream Dependencies via apt ---"
# These are general libraries that DeepStream needs, whether installed via apt or tarball.
# apt for DeepStream itself should pull most of its direct dependencies, but these are good to ensure.
sudo apt update # Ensure package lists are fresh before installing dependencies
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

# --- Install DeepStream SDK v7.1.0 via apt ---
echo "--- Installing DeepStream SDK v7.1.0 via apt ---"
# This assumes the NVIDIA APT repositories for JetPack are correctly configured.
# SDK Manager typically sets these up.
sudo apt install -y deepstream-7.1 || { echo "ERROR: Failed to install deepstream-7.1 via apt. Check your APT sources and network."; exit 1; }

echo "--- DeepStream Installation Complete! ---"
echo "You can verify the installation by running:"
echo "deepstream-app --version"
echo "Or check the DeepStream documentation for sample applications."

