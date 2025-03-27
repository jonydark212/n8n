#!/bin/bash

# Cài đặt N8n trên Ubuntu/Debian

# Thoát ngay lập tức nếu một lệnh thất bại và hiển thị lỗi
set -e
set -o pipefail
trap 'log "Lỗi xảy ra tại dòng $LINENO. Lệnh thất bại: \"$BASH_COMMAND\""' ERR

# Biến
NODE_VERSION="18.x"
N8N_PORT="5678"
USER_NAME=$(whoami) # Lấy username của người dùng hiện tại
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/n8n_install_${TIMESTAMP}.log"

# Hàm để hiển thị thông báo và ghi log
log() {
  echo -e "\e[1m[$(date +'%Y-%m-%d %H:%M:%S')] $1\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Kiểm tra quyền sudo
if [[ $EUID -ne 0 ]]; then
  log "Cần quyền sudo để chạy script này."
  exit 1
fi

# Kiểm tra hệ điều hành
if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
  log "Script này chỉ hỗ trợ Ubuntu hoặc Debian."
  exit 1
fi

# Cập nhật hệ thống
log "Cập nhật hệ thống..."
apt update && apt upgrade -y || {
  log "Không thể cập nhật hệ thống. Kiểm tra kết nối mạng và thử lại."
  exit 1
}

# Kiểm tra và cài đặt Node.js phiên bản phù hợp
log "Kiểm tra phiên bản Node.js..."
if ! command -v node &> /dev/null || [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt 18 ]]; then
  log "Cài đặt Node.js ${NODE_VERSION}..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash -
  apt install -y nodejs
fi

# Kiểm tra phiên bản Node.js sau khi cài đặt
NODE_CURRENT=$(node -v)
log "Phiên bản Node.js hiện tại: ${NODE_CURRENT}"

# Cài đặt các gói cần thiết
log "Cài đặt các gói cần thiết..."
apt install -y curl nginx npm pm2 build-essential python3

# Cài đặt N8n
log "Cài đặt N8n..."
npm install -g n8n || {
  log "Không thể cài đặt N8n. Kiểm tra lại kết nối mạng và thử lại."
  exit 1
}

# Kiểm tra cài đặt N8n
if ! command -v n8n &> /dev/null; then
  log "Cài đặt N8n thất bại. Kiểm tra lại và thử lại."
  exit 1
fi

log "Phiên bản N8n: $(n8n --version)"

# Tạo thư mục cấu hình N8n nếu chưa tồn tại
N8N_CONFIG_DIR="/home/${USER_NAME}/.n8n"
if [ ! -d "$N8N_CONFIG_DIR" ]; then
  log "Tạo thư mục cấu hình N8n..."
  mkdir -p "$N8N_CONFIG_DIR"
  chown -R ${USER_NAME}:${USER_NAME} "$N8N_CONFIG_DIR"
fi

# Cấu hình N8n service bằng systemd
log "Tạo cấu hình systemd cho N8n..."
cat << EOF | tee /etc/systemd/system/n8n.service
[Unit]
Description=N8N Workflow Automation
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
ExecStart=$(which n8n) start
WorkingDirectory=/home/${USER_NAME}
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=n8n
Environment=NODE_ENV=production

# Tăng cường bảo mật
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Kích hoạt và khởi động N8n service
log "Kích hoạt và khởi động N8n service..."
systemctl daemon-reload
systemctl enable n8n
systemctl start n8n || {
  log "Không thể khởi động N8n service. Kiểm tra lỗi với: systemctl status n8n"
  systemctl status n8n
  exit 1
}

# Kiểm tra trạng thái N8n service
log "Kiểm tra trạng thái N8n service..."
sleep 5
if ! systemctl is-active --quiet n8n; then
  log "N8n service không hoạt động. Kiểm tra lỗi với: systemctl status n8n"
  systemctl status n8n
  exit 1
fi

# Cấu hình Nginx
log "Tạo cấu hình Nginx cho N8n..."
cat << EOF | tee /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name localhost; # Thay đổi thành domain thật nếu có

    # Tối ưu hiệu suất
    client_max_body_size 50M;
    gzip on;
    gzip_comp_level 6;
    gzip_min_length 1000;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Bảo mật
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://localhost:${N8N_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 120s;
    }
}
EOF

# Kích hoạt cấu hình Nginx
log "Kích hoạt cấu hình Nginx..."
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n

# Kiểm tra cấu hình Nginx
if ! nginx -t; then
  log "Cấu hình Nginx không hợp lệ. Vui lòng kiểm tra lại."
  exit 1
fi

# Khởi động lại Nginx
systemctl restart nginx || {
  log "Không thể khởi động lại Nginx. Kiểm tra lỗi với: systemctl status nginx"
  systemctl status nginx
  exit 1
}

# Kiểm tra kết nối đến N8n
log "Kiểm tra kết nối đến N8n..."
sleep 5
if ! curl -s --head http://localhost | grep "200 OK" > /dev/null; then
  log "Cảnh báo: Không thể kết nối đến N8n qua Nginx. Kiểm tra lại cấu hình."
  log "Bạn có thể cần kiểm tra trạng thái N8n và Nginx:"
  log "  - systemctl status n8n"
  log "  - systemctl status nginx"
  log "  - curl -v http://localhost:${N8N_PORT}"
fi

log "N8n đã được cài đặt thành công!"
log "Truy cập http://localhost hoặc http://địa_chỉ_IP_của_bạn để sử dụng N8n"
log "Nhật ký cài đặt được lưu tại: ${LOG_FILE}"

# Hiển thị thông tin hữu ích
IP_ADDRESS=$(hostname -I | awk '{print $1}')
log "Thông tin hệ thống:"
log "  - Địa chỉ IP: ${IP_ADDRESS}"
log "  - N8n URL: http://${IP_ADDRESS}"
log "  - N8n Port: ${N8N_PORT}"
log "  - Phiên bản Node.js: $(node -v)"
log "  - Phiên bản N8n: $(n8n --version)"
