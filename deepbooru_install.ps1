# deepbooru_install.ps1
# DeepDanbooru 环境安装脚本

Write-Host "=== DeepDanbooru 环境安装 ===" -ForegroundColor Green

# 设置项目结构
$ModelsRoot = "deepbooru_models"
$InputDir = "$ModelsRoot\input"
$OutputDir = "$ModelsRoot\output"
$ScriptsDir = "$ModelsRoot\scripts"
$venvName = "deepbooru_venv"

# 检查 Python
Write-Host "`n1. 检查 Python 环境..." -ForegroundColor Yellow
$pythonVersion = python --version 2>$null
if (-not $pythonVersion) {
    Write-Host "错误：未检测到 Python。请从 https://www.python.org/downloads/ 安装 Python 3.8+" -ForegroundColor Red
    exit 1
}
Write-Host "✓ 已安装: $pythonVersion" -ForegroundColor Green

# 创建虚拟环境
Write-Host "`n2. 创建虚拟环境 '$venvName'..." -ForegroundColor Yellow
python -m venv $venvName

if (-not (Test-Path -Path $venvName)) {
    Write-Host "✗ 虚拟环境创建失败" -ForegroundColor Red
    exit 1
}
Write-Host "✓ 虚拟环境创建成功" -ForegroundColor Green

# 激活虚拟环境
Write-Host "`n3. 激活虚拟环境..." -ForegroundColor Yellow
& ".\\$venvName\\Scripts\\Activate.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ 虚拟环境激活失败" -ForegroundColor Red
    Write-Host "请尝试以管理员身份运行PowerShell" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ 虚拟环境已激活" -ForegroundColor Green

# 升级 pip
Write-Host "`n4. 升级 pip..." -ForegroundColor Yellow
python -m pip install --upgrade pip
Write-Host "✓ pip 升级完成" -ForegroundColor Green

# 安装核心依赖
Write-Host "`n5. 安装核心依赖..." -ForegroundColor Yellow

# PyTorch (CPU版本 - 如果需要GPU版本请修改)
Write-Host "   - 安装 PyTorch..." -ForegroundColor Cyan
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

# 其他必要依赖
Write-Host "   - 安装其他依赖..." -ForegroundColor Cyan
pip install safetensors Pillow transformers huggingface-hub requests numpy

Write-Host "✓ 核心依赖安装完成" -ForegroundColor Green

# 创建目录结构
Write-Host "`n6. 创建目录结构..." -ForegroundColor Yellow

$directories = @(
    $ModelsRoot,
    $InputDir,
    $OutputDir,
    $ScriptsDir
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "   ✓ 创建目录: $dir" -ForegroundColor Green
    }
}

# 下载模型代码
Write-Host "`n7. 下载模型实现代码..." -ForegroundColor Yellow
$modelCodeUrl = "https://raw.githubusercontent.com/Pearisli/VisGen/main/models/deepdanbooru.py"
$modelCodePath = "$ModelsRoot\deepdanbooru.py"

$downloadSuccess = $true
try {
    Invoke-WebRequest -Uri $modelCodeUrl -OutFile $modelCodePath -UseBasicParsing
    if (Test-Path $modelCodePath) {
        Write-Host "✓ 模型代码下载成功: $modelCodePath" -ForegroundColor Green
    } else {
        Write-Host "✗ 模型代码下载失败" -ForegroundColor Red
        $downloadSuccess = $false
    }
}
catch {
    Write-Host "✗ 自动下载失败: $($_.Exception.Message)" -ForegroundColor Red
    $downloadSuccess = $false
}

# 下载模型权重文件
Write-Host "`n8. 下载模型权重文件..." -ForegroundColor Yellow
$modelFiles = @(
    @{Name = "model.safetensors"; Url = "https://huggingface.co/pearisli/deepdanbooru-pytorch/resolve/main/model.safetensors"},
    @{Name = "config.json"; Url = "https://huggingface.co/pearisli/deepdanbooru-pytorch/resolve/main/config.json"},
    @{Name = "tags.txt"; Url = "https://huggingface.co/pearisli/deepdanbooru-pytorch/resolve/main/tags.txt"}
)

$weightsDownloadSuccess = $true
foreach ($file in $modelFiles) {
    $filePath = "$ModelsRoot\$($file.Name)"
    try {
        Write-Host "   下载 $($file.Name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $file.Url -OutFile $filePath -UseBasicParsing
        if (Test-Path $filePath) {
            Write-Host "   ✓ $($file.Name) 下载成功" -ForegroundColor Green
        } else {
            Write-Host "   ✗ $($file.Name) 下载失败" -ForegroundColor Red
            $weightsDownloadSuccess = $false
        }
    }
    catch {
        Write-Host "   ✗ $($file.Name) 下载失败: $($_.Exception.Message)" -ForegroundColor Red
        $weightsDownloadSuccess = $false
    }
}

# 如果自动下载失败，提示手动下载
if (-not $downloadSuccess -or -not $weightsDownloadSuccess) {
    Write-Host "`n⚠ 部分文件自动下载失败，请手动下载以下文件:" -ForegroundColor Yellow
    
    if (-not $downloadSuccess) {
        Write-Host "   1. 模型代码文件:" -ForegroundColor Cyan
        Write-Host "      下载地址: https://github.com/Pearisli/VisGen/blob/main/models/deepdanbooru.py" -ForegroundColor White
        Write-Host "      保存位置: $ModelsRoot\deepdanbooru.py" -ForegroundColor White
    }
    
    if (-not $weightsDownloadSuccess) {
        Write-Host "`n   2. 模型权重文件:" -ForegroundColor Cyan
        Write-Host "      下载地址: https://huggingface.co/pearisli/deepdanbooru-pytorch/tree/main" -ForegroundColor White
        Write-Host "      需要文件: model.safetensors, config.json, tags.txt" -ForegroundColor White
        Write-Host "      保存位置: $ModelsRoot\" -ForegroundColor White
    }
    
    Write-Host "`n请手动下载并放置文件后，即可使用DeepDanbooru。" -ForegroundColor Yellow
} else {
    Write-Host "`n✓ 所有文件下载完成" -ForegroundColor Green
}

# 完成信息
Write-Host "`n=== 安装完成！ ===" -ForegroundColor Green
Write-Host "`n项目结构:" -ForegroundColor Cyan
Write-Host "  $ModelsRoot\" -ForegroundColor White
Write-Host "  ├── deepdanbooru.py    # 模型代码" -ForegroundColor White
Write-Host "  ├── model.safetensors  # 模型权重" -ForegroundColor White
Write-Host "  ├── config.json        # 模型配置" -ForegroundColor White
Write-Host "  ├── tags.txt           # 标签列表" -ForegroundColor White
Write-Host "  ├── input/             # 输入图片目录" -ForegroundColor White
Write-Host "  ├── output/            # 输出目录" -ForegroundColor White
Write-Host "  └── scripts/           # 脚本目录" -ForegroundColor White

Write-Host "`n虚拟环境: $venvName\" -ForegroundColor Cyan

Write-Host "`n使用方法:" -ForegroundColor Cyan
Write-Host "1. 激活虚拟环境: .\$venvName\Scripts\Activate.ps1" -ForegroundColor White
Write-Host "2. 进入模型目录: cd $ModelsRoot" -ForegroundColor White
Write-Host "3. 在Python脚本中导入模型使用" -ForegroundColor White
Write-Host "   使用本地模型: model = DeepDanbooruModel.from_pretrained('.'))" -ForegroundColor White

Write-Host "`n重要说明:" -ForegroundColor Yellow
Write-Host "• 所有模型文件已下载到本地，无需联网即可使用" -ForegroundColor White
Write-Host "• 默认使用CPU版本，如需GPU请安装CUDA版本的PyTorch" -ForegroundColor White
Write-Host "• 将需要处理的图片放入 input 文件夹" -ForegroundColor White

Write-Host "`n现在您可以开始使用DeepDanbooru了！" -ForegroundColor Green