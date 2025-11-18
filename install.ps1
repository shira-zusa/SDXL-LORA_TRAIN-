# install.ps1 - SDXL LoRA Environment Setup for Intel ARC GPU

# Set environment variables
$Env:HF_HOME = "huggingface"

# Create virtual environment if it doesn't exist
if (!(Test-Path -Path "venv")) {
    Write-Output "Creating Python virtual environment..."
    python -m venv venv
}

# Activate virtual environment
.\venv\Scripts\activate

# Upgrade pip first
Write-Output "Upgrading pip..."
python -m pip install --upgrade pip

Write-Output "Installing dependencies for Intel ARC GPU..."

# 先卸载可能存在的冲突版本
Write-Output "Cleaning up existing packages..."
pip uninstall torch torchvision torchaudio intel-extension-for-pytorch -y

# 安装兼容版本的PyTorch和IPEX
Write-Output "Installing compatible PyTorch and IPEX versions..."

# 方法1: 安装可用的兼容版本
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/xpu

# 方法2: 安装可用的IPEX版本
pip install intel-extension-for-pytorch --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/

# 检查安装的版本并记录
Write-Output "Recording installed versions..."
python -c "
import torch
print(f'Installed PyTorch: {torch.__version__}')
try:
    import intel_extension_for_pytorch as ipex
    print(f'Installed IPEX: {ipex.__version__}')
except ImportError as e:
    print(f'IPEX import error: {e}')
"

# Install core dependencies
Write-Output "Installing core AI libraries..."
pip install diffusers transformers accelerate datasets
pip install peft
pip install pillow opencv-python safetensors huggingface-hub

# Install additional training dependencies
Write-Output "Installing additional training dependencies..."
pip install bitsandbytes
pip install wandb
pip install lion-pytorch
pip install invisible_watermark

# Install additional utilities
Write-Output "Installing utility packages..."
pip install requests beautifulsoup4 tqdm numpy pandas
pip install tensorboard

# Create project folders
Write-Output "Creating project folders..."
$folders = @("data", "data/train_data", "data/images", "output", "lora-output", "models", "scripts")
foreach ($folder in $folders) {
    if (!(Test-Path -Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

# Create README.md with simple content
$readmeContent = @"
# SDXL LoRA Training Project (Intel ARC GPU)

## Project Structure
- data/ - Training data
- data/images/ - Training images
- data/train_data/ - Additional training data
- output/ - Training outputs
- lora-output/ - TensorBoard logs
- models/ - Base models
- scripts/ - Training scripts

## Environment
- Python 3.11+
- PyTorch with Intel XPU support
- Intel Extension for PyTorch
- Intel ARC GPU optimized

## Quick Start
1. Place training images in 'data/images/'
2. Add training scripts to 'scripts/'
3. Run training with: accelerate launch scripts/train_lora.py

## Troubleshooting
If you get version mismatch warnings, check installed versions with:
python -c `"import torch; print(f'PyTorch: {torch.__version__}'); import intel_extension_for_pytorch as ipex; print(f'IPEX: {ipex.__version__}')`"
"@

$readmeContent | Out-File -FilePath "README.md" -Encoding utf8

# Create improved test script
$testScript = @'
# test_environment.py - Enhanced environment test
import sys
import torch
import subprocess
import pkg_resources

def get_package_version(package_name):
    try:
        return pkg_resources.get_distribution(package_name).version
    except:
        return "Not installed"

def main():
    print("=" * 50)
    print("Environment Test for SDXL LoRA Training")
    print("=" * 50)
    
    # Python and basic info
    print(f"Python: {sys.version.split()[0]}")
    print(f"PyTorch: {torch.__version__}")
    
    # Check XPU availability
    if hasattr(torch, 'xpu') and torch.xpu.is_available():
        print(f"✅ XPU is available!")
        print(f"XPU Device: {torch.xpu.get_device_name(0)}")
        print(f"Available XPU devices: {torch.xpu.device_count()}")
        
        # Get XPU memory info
        xpu_props = torch.xpu.get_device_properties(0)
        print(f"XPU Memory: {xpu_props.total_memory / 1024**3:.2f} GB")
        
        # Test basic tensor operations
        try:
            test_tensor = torch.randn(3, 3, device='xpu')
            result = test_tensor * 2
            print("✅ Basic XPU operations working correctly")
        except Exception as e:
            print(f"❌ XPU operations failed: {e}")
    else:
        print("❌ XPU not available")
        print("Available devices:")
        if torch.cuda.is_available():
            print(f"  CUDA: {torch.cuda.device_count()} devices")
        else:
            print("  No CUDA devices")
    
    print("\n" + "=" * 50)
    print("Key Package Versions:")
    print("=" * 50)
    
    key_packages = [
        "torch", "torchvision", "torchaudio", 
        "intel-extension-for-pytorch",
        "diffusers", "transformers", "accelerate",
        "peft", "datasets"
    ]
    
    for package in key_packages:
        version = get_package_version(package)
        print(f"{package:30} {version}")
    
    print("\n" + "=" * 50)
    
    # Check for version compatibility
    try:
        import intel_extension_for_pytorch as ipex
        torch_version = torch.__version__
        ipex_version = ipex.__version__
        
        # Simple version compatibility check
        if torch_version.startswith("2.") and ipex_version.startswith("2."):
            print("✅ PyTorch and IPEX versions are compatible")
        else:
            print("⚠️  Potential version compatibility issue")
            
    except ImportError:
        print("❌ Intel Extension for PyTorch not installed")
    
    # Final check
    if hasattr(torch, 'xpu') and torch.xpu.is_available():
        print("🎉 Environment is ready for SDXL LoRA training!")
        print("Next: Add training scripts and data, then run training")
    else:
        print("⚠️  Environment issues detected")
        print("Please check Intel GPU drivers and installation")

if __name__ == "__main__":
    main()
'@

$testScript | Out-File -FilePath "test_environment.py" -Encoding utf8

Write-Output "Installation completed!"
Write-Output " "
Write-Output "Next steps:"
Write-Output "1. Test environment: python test_environment.py"
Write-Output "2. If versions don't match, you may need to manually adjust"
Write-Output "3. Add training scripts to 'scripts' folder"
Write-Output "4. Add training images to 'data/images' folder"
Write-Output "5. Download base model to 'models' folder"

Write-Output " "
Write-Output "Note: If version warnings persist, check available versions with:"
Write-Output "pip index versions torch --index-url https://download.pytorch.org/whl/xpu"
Write-Output "pip index versions intel-extension-for-pytorch --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/"

Write-Output " "
pause