#!/usr/bin/env pwsh
# 增强版SDXL LoRA训练脚本 - 稳定器优化版本 + 中心裁剪
# 默认启用中心裁剪，禁用随机裁剪

# =============================================
# 脚本参数定义区域
# =============================================

param(
    [string]$DataDir = ".\data\train_data",
    [string]$OutputDir = ".\lora-output",
    [string]$ModelPath = ".\models\stable-diffusion-xl-base-1.0",
    [int]$BatchSize = 1,
    [int]$MaxSteps = 800,
    [string]$ValidationPrompt = "gzchf, loli ,blue eyes,catgirl,wearing white dress,white pantyhose,panty under pantyhose,sitting,legs apart,leg up,prefect background",
    [string]$LoraName = "gzchf",
    [string]$FinalOutputDir = ".\output",
    [switch]$ForceRestart = $false,
    [switch]$EnableTensorboard = $true,
    [int]$TensorboardPort = 6006,
    # 新增稳定器参数
    [float]$LearningRate = 1.5e-5,
    [string]$LrScheduler = "constant_with_warmup",
    [int]$LrWarmupSteps = 48,
    [int]$GradientAccumulationSteps = 4,
    [float]$MaxGradNorm = 0.08,
    [float]$SnrGamma = 4.0,
    # 新增裁剪参数 - 默认启用中心裁剪
    [switch]$CenterCrop = $true,
    [switch]$RandomFlip = $false,
    [string]$InterpolationMode = "lanczos"
)

# =============================================
# 函数定义区域
# =============================================

# 断点重连检测函数
function Test-ResumeTraining {
    param([string]$OutputDir)
    
    Write-Host "检查是否存在可恢复的检查点..." -ForegroundColor Cyan
    
    $checkpoints = Get-ChildItem $OutputDir -Directory | Where-Object { $_.Name -like "checkpoint-*" }
    
    if ($checkpoints) {
        $latestCheckpoint = $checkpoints | Sort-Object { [int]($_.Name -replace 'checkpoint-', '') } -Descending | Select-Object -First 1
        
        Write-Host "发现检查点: $($latestCheckpoint.Name)" -ForegroundColor Yellow
        
        $checkpointStep = $latestCheckpoint.Name -replace 'checkpoint-', ''
        $confirm = Read-Host "是否从步骤 $checkpointStep 继续训练？(Y/n)"
        
        if ($confirm -eq '' -or $confirm -eq 'y' -or $confirm -eq 'Y') {
            Write-Host "选择从检查点继续训练" -ForegroundColor Green
            return "latest"
        } else {
            Write-Host "选择重新开始训练" -ForegroundColor Cyan
        }
    } else {
        Write-Host "未发现检查点，开始新的训练" -ForegroundColor Cyan
    }
    
    return $null
}

# TensorBoard启动函数
function Start-TensorBoard {
    param([int]$Port, [string]$SessionID)
    
    Write-Host "启动 TensorBoard 监控..." -ForegroundColor Cyan
    
    $actualLogDir = "$OutputDir\logs\$SessionID\text2image-fine-tune"
    
    if (-not (Test-Path $actualLogDir)) {
        New-Item -ItemType Directory -Path $actualLogDir -Force | Out-Null
    }
    
    $portInUse = Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet
    if ($portInUse) {
        $Port = $Port + 1
    }
    
    $tensorboardProcess = Start-Process -FilePath "tensorboard" `
        -ArgumentList "--logdir=$actualLogDir", "--port=$Port", "--bind_all", "--reload_interval=5" `
        -PassThru -NoNewWindow
    
    Start-Sleep -Seconds 3
    
    return @{
        Process = $tensorboardProcess
        Port = $Port
        URL = "http://localhost:$Port"
        LogDir = $actualLogDir
    }
}

# 实时损失监控函数
function Start-LossMonitor {
    param([string]$SessionID, [string]$LogFile = "loss_log.json")
    
    @{"loss_history" = @(); "session" = $SessionID; "start_time" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")} | 
        ConvertTo-Json | Out-File -FilePath $LogFile -Encoding UTF8
    
    return @{
        LogFile = $LogFile
        SessionID = $SessionID
    }
}

# 更新损失数据函数
function Update-LossData {
    param([hashtable]$MonitorInfo, [int]$Step, [float]$Loss)
    
    try {
        $lossData = Get-Content $MonitorInfo.LogFile | ConvertFrom-Json
        
        $newEntry = @{
            "step" = $Step
            "loss" = $Loss
            "timestamp" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        
        $lossData.loss_history += $newEntry
        $lossData | ConvertTo-Json | Out-File -FilePath $MonitorInfo.LogFile -Encoding UTF8
    } catch {
        # 静默失败
    }
}

# 训练完成检测函数
function Test-TrainingSuccess {
    param([string]$OutputDir, [int]$MaxSteps, [string]$TrainingLogFile)
    
    Write-Host "分析训练完成状态..." -ForegroundColor Cyan
    
    $loraFiles = Get-ChildItem $OutputDir -Filter "*.safetensors" -Recurse -ErrorAction SilentlyContinue
    if ($loraFiles) {
        Write-Host "找到LoRA模型文件: $($loraFiles.Count) 个" -ForegroundColor Green
        return $true
    }
    
    if (Test-Path $TrainingLogFile) {
        $logContent = Get-Content $TrainingLogFile -Encoding UTF8 -Tail 50
        
        $completionIndicators = @(
            "达到最大训练步骤",
            "训练完成", 
            "训练流程完成",
            "LoRA 权重已保存",
            "Model weights saved"
        )
        
        foreach ($indicator in $completionIndicators) {
            if ($logContent -match $indicator) {
                return $true
            }
        }
        
        if ($logContent -match "Steps:\s+100%") {
            return $true
        }
    }
    
    return $false
}

# =============================================
# 主脚本逻辑区域
# =============================================

Write-Host "SDXL LoRA 训练启动 - 稳定器优化版 + 中心裁剪" -ForegroundColor Green
Write-Host "启用的稳定器参数:" -ForegroundColor Yellow
Write-Host "  - 学习率: $LearningRate" -ForegroundColor Cyan
Write-Host "  - 学习率调度器: $LrScheduler" -ForegroundColor Cyan
Write-Host "  - 学习率预热步数: $LrWarmupSteps" -ForegroundColor Cyan
Write-Host "  - 梯度累积步数: $GradientAccumulationSteps" -ForegroundColor Cyan
Write-Host "  - 最大梯度范数: $MaxGradNorm" -ForegroundColor Cyan
Write-Host "  - SNR Gamma: $SnrGamma" -ForegroundColor Cyan
Write-Host "启用的裁剪参数:" -ForegroundColor Yellow
Write-Host "  - 中心裁剪: 启用" -ForegroundColor Green
Write-Host "  - 随机翻转: 禁用" -ForegroundColor Red
Write-Host "  - 插值模式: $InterpolationMode" -ForegroundColor Cyan

if (-not (Test-Path $FinalOutputDir)) {
    New-Item -ItemType Directory -Path $FinalOutputDir -Force | Out-Null
}

$TrainingID = Get-Date -Format "yyyyMMdd_HHmmss"
$TrainingSession = "${LoraName}_${TrainingID}"

Write-Host "训练会话: $TrainingSession" -ForegroundColor Yellow

$resumeFrom = $null
if (!$ForceRestart) {
    $resumeFrom = Test-ResumeTraining -OutputDir $OutputDir
}

# =============================================
# 训练参数配置 - 启用了所有稳定器 + 中心裁剪
# =============================================

$TrainingArgs = @(
    "--pretrained_model_name_or_path", $ModelPath,
    "--train_data_dir", $DataDir,
    "--output_dir", $OutputDir,
    "--resolution", "1024",
    "--train_batch_size", $BatchSize.ToString(),
    "--gradient_accumulation_steps", $GradientAccumulationSteps.ToString(),
    "--max_train_steps", $MaxSteps.ToString(),
    "--checkpointing_steps", "200",
    # 学习率相关稳定器
    "--learning_rate", $LearningRate.ToString(),
    "--lr_scheduler", $LrScheduler,
    "--lr_warmup_steps", $LrWarmupSteps.ToString(),
    # 梯度稳定器
    "--max_grad_norm", $MaxGradNorm.ToString(),
    # 损失函数稳定器
    "--snr_gamma", $SnrGamma.ToString(),
    # 裁剪参数 - 默认启用中心裁剪，禁用随机翻转
    "--center_crop",
    "--image_interpolation_mode", $InterpolationMode,
    # 其他优化参数
    "--mixed_precision", "bf16",
    "--gradient_checkpointing",
    "--allow_tf32",
    "--dataloader_num_workers", "0",
    "--report_to", "tensorboard",
    "--logging_dir", "logs\$TrainingSession"
)

# 只有在明确启用时才添加随机翻转
if ($RandomFlip) {
    $TrainingArgs += "--random_flip"
    Write-Host "  - 随机翻转: 启用" -ForegroundColor Green
}

if ($resumeFrom) {
    $TrainingArgs += "--resume_from_checkpoint"
    $TrainingArgs += $resumeFrom
}

$SessionInfo = @{
    training_id = $TrainingSession
    lora_name = $LoraName
    data_dir = $DataDir
    output_dir = $OutputDir
    final_output_dir = $FinalOutputDir
    batch_size = $BatchSize
    max_steps = $MaxSteps
    resume_from = if ($resumeFrom) { $resumeFrom } else { "new_training" }
    start_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    validation_prompt = $ValidationPrompt
    tensorboard_enabled = $EnableTensorboard
    tensorboard_port = $TensorboardPort
    # 记录稳定器配置
    stabilizers_enabled = @{
        learning_rate = $LearningRate
        lr_scheduler = $LrScheduler
        lr_warmup_steps = $LrWarmupSteps
        gradient_accumulation_steps = $GradientAccumulationSteps
        max_grad_norm = $MaxGradNorm
        snr_gamma = $SnrGamma
    }
    # 记录裁剪配置
    crop_settings = @{
        center_crop = $true
        random_flip = $RandomFlip
        interpolation_mode = $InterpolationMode
    }
}

$SessionInfo | ConvertTo-Json | Out-File "$FinalOutputDir\${TrainingSession}_info.json" -Encoding UTF8

$TensorboardInfo = $null
if ($EnableTensorboard) {
    $TensorboardInfo = Start-TensorBoard -Port $TensorboardPort -SessionID $TrainingSession
}

$LossMonitorInfo = Start-LossMonitor -SessionID $TrainingSession

$trainingSuccess = $false
$trainingError = $null
$TrainingLogFile = "training_output_$TrainingSession.log"

try {
    Write-Host "开始训练（稳定器+中心裁剪已启用）..." -ForegroundColor Green
    
    $TrainingLogFile = "training_output_$TrainingSession.log"
    $fullArgs = @("sdxl_lora_training.py") + $TrainingArgs
    
    $trainingProcess = Start-Process -FilePath "python" `
        -ArgumentList $fullArgs `
        -PassThru -NoNewWindow -RedirectStandardOutput $TrainingLogFile
    
    $lastFileSize = 0
    while (!$trainingProcess.HasExited) {
        Start-Sleep -Milliseconds 500
        
        if (Test-Path $TrainingLogFile) {
            $currentSize = (Get-Item $TrainingLogFile).Length
            
            if ($currentSize -gt $lastFileSize) {
                $newContent = Get-Content $TrainingLogFile -Encoding UTF8 | Select-Object -Last 50
                
                foreach ($line in $newContent) {
                    Write-Host $line
                    
                    if ($line -match "Steps:.*?(\d+)/\d+.*?step_loss=([\d\.eE+-]+)") {
                        $step = [int]$matches[1]
                        $loss = [float]$matches[2]
                        Update-LossData -MonitorInfo $LossMonitorInfo -Step $step -Loss $loss
                    }
                }
                
                $lastFileSize = $currentSize
            }
        }
        
        if ($trainingProcess.HasExited) {
            break
        }
    }
    
    $trainingProcess.WaitForExit()
    
    $isTrainingSuccessful = Test-TrainingSuccess -OutputDir $OutputDir -MaxSteps $MaxSteps -TrainingLogFile $TrainingLogFile
    
    if ($isTrainingSuccessful -or $trainingProcess.ExitCode -eq 0) {
        Write-Host "训练完成! 文件位置: $OutputDir" -ForegroundColor Green
        $trainingSuccess = $true
    } else {
        $trainingError = "训练失败，退出代码: $($trainingProcess.ExitCode)"
    }
}
catch {
    $trainingError = $_.Exception.Message
}

# 静默清理资源
try {
    if ($TensorboardInfo -ne $null -and $TensorboardInfo.Process -ne $null) {
        if (!$TensorboardInfo.Process.HasExited) {
            $TensorboardInfo.Process.Kill()
        }
    }
}
catch {
    # 静默失败
}

$tempFiles = @(
    "training_output_$TrainingSession.log",
    "training_error_$TrainingSession.log", 
    "loss_log.json"
)

foreach ($tempFile in $tempFiles) {
    try {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # 静默失败
    }
}

# =============================================
# 静默退出区域 - 无输出
# =============================================

$TrainingStatusFile = "$FinalOutputDir\${TrainingSession}_status.txt"

if ($trainingSuccess) {
    "1" | Out-File -FilePath $TrainingStatusFile -Encoding UTF8
    exit 0
} elseif ($trainingError) {
    "0" | Out-File -FilePath $TrainingStatusFile -Encoding UTF8
    exit 1
} else {
    "0" | Out-File -FilePath $TrainingStatusFile -Encoding UTF8
    exit 2
}