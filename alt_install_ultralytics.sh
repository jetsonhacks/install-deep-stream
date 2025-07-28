#!/bin/bash

# This script installs Ultralytics natively on Jetson Orin Nano with JetPack 6.2,
# using specific PyTorch, TorchVision, ONNX Runtime GPU wheels from Ultralytics assets,
# and including the CUDA keyring for NVIDIA APT repositories.

# --- Configuration ---
ULTRA_REPO="https://github.com/ultralytics/ultralytics.git"
ULTRA_DIR="ultralytics"

# Specific wheel URLs from Ultralytics assets as provided by the user
ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.20.0-cp310-cp310-linux_aarch64.whl"
TORCH_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
TORCHVISION_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"

# CUDA Keyring URL (for Ubuntu 22.04 arm64, compatible with JetPack 6.x)
CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-keyring_1.1-1_all.deb"


# --- Script Start ---
echo "Starting Ultralytics native installation on Jetson Orin Nano with JetPack 6.2..."

# 0. Ensure script exits on error
set -e

# Create a temporary directory for downloads
mkdir -p /tmp/ultralytics_install_temp
pushd /tmp/ultralytics_install_temp

# 1. Install CUDA Keyring and Update APT
echo "1. Installing CUDA Keyring and updating APT..."
wget "$CUDA_KEYRING_URL" -O cuda-keyring_1.1-1_all.deb || { echo "Failed to download cuda-keyring. Exiting."; exit 1; }
sudo dpkg -i cuda-keyring_1.1-1_all.deb || { echo "Failed to install cuda-keyring. Exiting."; exit 1; }
sudo apt update -y || { echo "Failed to update apt repositories. Exiting."; exit 1; }

echo "CUDA Keyring installed and APT repositories updated."

# 2. Install System Dependencies
echo "2. Installing system dependencies..."
sudo apt install -y \
    git \
    python3-pip \
    libopenmpi-dev \
    libopenblas-base \
    libomp-dev \
    libcusparselt0 \
    libcusparsparset-dev \
    libjpeg-dev \
    zlib1g-dev \
    libpython3-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    build-essential # Good to have for compiling extensions

echo "System dependencies installed."

# 3. Upgrade pip and install numpy
echo "3. Upgrading pip and installing compatible numpy..."
pip install --upgrade pip
pip install 'numpy<2' # Important for compatibility with some PyTorch versions

# 4. Download and Install PyTorch, TorchVision, and ONNX Runtime GPU
echo "4. Downloading and installing PyTorch, TorchVision, and ONNX Runtime GPU..."

wget "$TORCH_WHL_URL" -O torch_jetson.whl || { echo "Failed to download PyTorch wheel. Exiting."; exit 1; }
wget "$TORCHVISION_WHL_URL" -O torchvision_jetson.whl || { echo "Failed to download TorchVision wheel. Exiting."; exit 1; }
wget "$ONNXRUNTIME_GPU_WHL_URL" -O onnxruntime_gpu_jetson.whl || { echo "Failed to download ONNX Runtime GPU wheel. Exiting."; exit 1; }

# Install wheels. --no-deps is good practice for locally sourced wheels,
# ensuring pip doesn't try to resolve dependencies from PyPI for these specific packages.
# --force-reinstall ensures existing versions are overwritten.
pip install --force-reinstall --no-cache-dir --no-deps \
    ./torch_jetson.whl \
    ./torchvision_jetson.whl \
    ./onnxruntime_gpu_jetson.whl || { echo "Failed to install PyTorch/TorchVision/ONNX Runtime GPU. Exiting."; exit 1; }

popd # Return to original directory
rm -rf /tmp/ultralytics_install_temp # Clean up downloaded wheels

echo "PyTorch, TorchVision, and ONNX Runtime GPU installed. Verifying..."
python3 -c "import torch; print('Torch Version:', torch.__version__); print('CUDA Available:', torch.cuda.is_available()); import torchvision; print('TorchVision Version:', torchvision.__version__); import onnxruntime; print('ONNX Runtime Version:', onnxruntime.__version__)" || { echo "PyTorch/TorchVision/ONNX Runtime verification failed. Exiting."; exit 1; }

if python3 -c "import torch; exit(not torch.cuda.is_available())"; then
    echo "CUDA is available for PyTorch. Proceeding."
else
    echo "WARNING: CUDA is NOT available for PyTorch. Please troubleshoot your PyTorch installation or JetPack setup."
    # Optionally exit here if CUDA is strictly required
    # exit 1
fi

# 5. Clone Ultralytics Repository
echo "5. Cloning Ultralytics repository..."
if [ -d "$ULTRA_DIR" ]; then
    echo "Existing Ultralytics directory found. Removing it and re-cloning."
    rm -rf "$ULTRA_DIR"
fi
git clone "$ULTRA_REPO" "$ULTRA_DIR" || { echo "Failed to clone Ultralytics repository. Exiting."; exit 1; }
cd "$ULTRA_DIR" || { echo "Failed to change directory to $ULTRA_DIR. Exiting."; exit 1; }

# 6. Install Ultralytics with Export Dependencies
echo "6. Installing Ultralytics with export dependencies..."
# Pip will now read pyproject.toml and install other remaining dependencies.
# Since torch, torchvision, and onnxruntime-gpu are already installed,
# pip should recognize them as satisfied and skip reinstalling from PyPI.
pip install -e '.[export]' || { echo "Failed to install Ultralytics with export dependencies. Exiting."; exit 1; }

# 7. Install Fonts (Optional, for full visualization features)
echo "7. Installing Arial fonts (optional, for plotting/visualization)..."
mkdir -p ~/.config/Ultralytics/
# Note: Arial fonts are proprietary. You might need to source these from a licensed copy.
# Example: cp /mnt/c/Windows/Fonts/arial.ttf ~/.config/Ultralytics/
# Example: cp /mnt/c/Windows/Fonts/arialuni.ttf ~/.config/Ultralytics/arial.unicode.ttf
echo "If you have Arial.ttf and Arial.Unicode.ttf, copy them to ~/.config/Ultralytics/ for full plotting functionality."

echo "Ultralytics installation complete!"
echo "You can now navigate to the '$ULTRA_DIR' directory and start using Ultralytics."
echo "Example: python3 -c \"from ultralytics import YOLO; model = YOLO('yolov8n.pt'); model.predict('https://ultralytics.com/images/bus.jpg')\""
