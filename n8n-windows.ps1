# Script cài đặt N8n trên Windows

# Kiểm tra quyền admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Cần quyền Administrator để chạy script này. Vui lòng chạy PowerShell với quyền Administrator."
    exit 1
}

# Tạo file log
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$env:TEMP\n8n_install_$timestamp.log"

# Hàm ghi log
function Write-Log {
    param(
        [string]$Message
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timeStamp] $Message" -ForegroundColor Cyan
    "[$timeStamp] $Message" | Out-File -FilePath $logFile -Append
}

# Biến cấu hình
$n8nPort = 5678
$nodeVersion = "18.x"
$n8nServiceName = "n8n"

# Bắt đầu cài đặt
Write-Log "Bắt đầu cài đặt N8n trên Windows..."

# Kiểm tra Node.js
try {
    $nodeInstalled = $null -ne (Get-Command node -ErrorAction SilentlyContinue)
    if ($nodeInstalled) {
        $currentVersion = (node -v).Substring(1)
        $majorVersion = [int]($currentVersion.Split(".")[0])
        Write-Log "Phiên bản Node.js hiện tại: v$currentVersion"
        
        if ($majorVersion -lt 18) {
            Write-Log "Cần Node.js phiên bản 18 trở lên. Đang cài đặt phiên bản mới..."
            $nodeInstalled = $false
        }
    }
    
    if (-not $nodeInstalled) {
        Write-Log "Đang cài đặt Node.js..."
        # Tải và cài đặt Node.js
        $nodejsUrl = "https://nodejs.org/dist/latest-v18.x/node-v18.18.2-x64.msi"
        $nodejsInstaller = "$env:TEMP\nodejs_installer.msi"
        
        Invoke-WebRequest -Uri $nodejsUrl -OutFile $nodejsInstaller
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $nodejsInstaller, "/quiet", "/norestart" -Wait
        
        # Làm mới biến môi trường PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Kiểm tra cài đặt
        $nodeVersion = (node -v)
        Write-Log "Node.js đã được cài đặt: $nodeVersion"
    }
}
catch {
    Write-Log "Lỗi khi kiểm tra/cài đặt Node.js: $_"
    exit 1
}

# Cài đặt các công cụ cần thiết
Write-Log "Cài đặt các công cụ cần thiết..."
try {
    # Kiểm tra và cài đặt npm nếu cần
    if ($null -eq (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Log "npm không được tìm thấy. Vui lòng cài đặt lại Node.js."
        exit 1
    }
    
    # Cài đặt node-windows để tạo dịch vụ
    Write-Log "Cài đặt node-windows..."
    npm install -g node-windows
    
    # Cài đặt PM2 (tùy chọn)
    Write-Log "Cài đặt PM2..."
    npm install -g pm2
}
catch {
    Write-Log "Lỗi khi cài đặt các công cụ: $_"
    exit 1
}

# Cài đặt N8n
Write-Log "Cài đặt N8n..."
try {
    npm install -g n8n
    
    # Kiểm tra cài đặt
    $n8nVersion = (n8n --version)
    if ($null -eq $n8nVersion) {
        Write-Log "Không thể xác minh cài đặt N8n. Kiểm tra lại."
        exit 1
    }
    Write-Log "N8n đã được cài đặt: $n8nVersion"
}
catch {
    Write-Log "Lỗi khi cài đặt N8n: $_"
    exit 1
}

# Tạo thư mục cấu hình
$n8nConfigDir = "$env:USERPROFILE\.n8n"
if (-not (Test-Path $n8nConfigDir)) {
    Write-Log "Tạo thư mục cấu hình N8n..."
    New-Item -ItemType Directory -Path $n8nConfigDir -Force | Out-Null
}

# Tạo file khởi động N8n
$n8nStartupScript = "$env:USERPROFILE\n8n-start.js"
Write-Log "Tạo script khởi động N8n..."
@"
const { Service } = require('node-windows');

// Tạo dịch vụ mới
const svc = new Service({
  name: 'N8n Workflow Automation',
  description: 'N8n Workflow Automation Platform',
  script: require('which').sync('n8n'),
  scriptOptions: 'start',
  env: [
    {
      name: "NODE_ENV",
      value: "production"
    },
    {
      name: "N8N_PORT",
      value: "$n8nPort"
    }
  ]
});

// Sự kiện
svc.on('install', () => {
  console.log('Dịch vụ N8n đã được cài đặt.');
  svc.start();
});

svc.on('start', () => {
  console.log('Dịch vụ N8n đã được khởi động.');
});

svc.on('error', (err) => {
  console.error('Lỗi dịch vụ N8n:', err);
});

// Cài đặt dịch vụ
svc.install();
"@ | Out-File -FilePath $n8nStartupScript -Encoding utf8

# Cài đặt N8n như một dịch vụ Windows
Write-Log "Cài đặt N8n như một dịch vụ Windows..."
try {
    # Cài đặt which để script node-windows hoạt động
    npm install -g which
    
    # Tạo thư mục cho dịch vụ
    $serviceDir = "$env:USERPROFILE\n8n-service"
    if (-not (Test-Path $serviceDir)) {
        New-Item -ItemType Directory -Path $serviceDir -Force | Out-Null
    }
    
    # Di chuyển vào thư mục dịch vụ
    Set-Location $serviceDir
    
    # Khởi tạo package.json
    if (-not (Test-Path "$serviceDir\package.json")) {
        @"
{
  "name": "n8n-windows-service",
  "version": "1.0.0",
  "description": "N8n Windows Service",
  "main": "index.js",
  "dependencies": {
    "node-windows": "^1.0.0",
    "which": "^2.0.2"
  }
}
"@ | Out-File -FilePath "$serviceDir\package.json" -Encoding utf8
    }
    
    # Cài đặt dependencies
    npm install
    
    # Chạy script cài đặt dịch vụ
    Copy-Item $n8nStartupScript "$serviceDir\install-service.js"
    node "$serviceDir\install-service.js"
    
    Write-Log "Đã cài đặt N8n như một dịch vụ Windows."
}
catch {
    Write-Log "Lỗi khi cài đặt N8n như một dịch vụ: $_"
    Write-Log "Bạn có thể chạy N8n thủ công bằng lệnh: n8n start"
}

# Kiểm tra dịch vụ
Start-Sleep -Seconds 5
$service = Get-Service -Name "n8n*" -ErrorAction SilentlyContinue
if ($null -ne $service) {
    Write-Log "Dịch vụ N8n đã được tạo: $($service.Name) - $($service.Status)"
    
    if ($service.Status -ne "Running") {
        Write-Log "Khởi động dịch vụ N8n..."
        Start-Service -Name $service.Name
    }
}
else {
    Write-Log "Không tìm thấy dịch vụ N8n. Bạn có thể chạy N8n thủ công bằng lệnh: n8n start"
}

# Kiểm tra kết nối
Start-Sleep -Seconds 5
try {
    $testConnection = Invoke-WebRequest -Uri "http://localhost:$n8nPort" -UseBasicParsing -ErrorAction SilentlyContinue
    if ($testConnection.StatusCode -eq 200) {
        Write-Log "N8n đang chạy và có thể truy cập tại http://localhost:$n8nPort"
    }
}
catch {
    Write-Log "Không thể kết nối đến N8n. Có thể dịch vụ chưa khởi động hoàn toàn."
    Write-Log "Vui lòng kiểm tra lại sau vài phút hoặc khởi động lại dịch vụ."
}

# Hiển thị thông tin
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "*Ethernet*", "*Wi-Fi*" | Where-Object { $_.IPAddress -notmatch "^169" } | Select-Object -First 1).IPAddress
if ([string]::IsNullOrEmpty($ipAddress)) {
    $ipAddress = "localhost"
}

Write-Log "Cài đặt N8n hoàn tất!"
Write-Log "Thông tin hệ thống:"
Write-Log "  - Địa chỉ IP: $ipAddress"
Write-Log "  - N8n URL: http://$ipAddress:$n8nPort"
Write-Log "  - Phiên bản Node.js: $(node -v)"
Write-Log "  - Phiên bản N8n: $(n8n --version)"
Write-Log "  - Nhật ký cài đặt: $logFile"

Write-Log "Để khởi động/dừng dịch vụ N8n, sử dụng lệnh:"
Write-Log "  - Start-Service -Name 'n8n*'"
Write-Log "  - Stop-Service -Name 'n8n*'"