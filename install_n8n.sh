#!/bin/bash

# Cài đặt N8n trên Ubuntu/Debian

# Thoát ngay lập tức nếu một lệnh thất bại
set -e

# Biến
NODE_VERSION="18.x"
N8N_PORT="5678"
USER_NAME=$(whoami) # Lấy username của người dùng hiện tại

# Hàm để hiển thị thông báo
log() {
  echo -e "\e[1m[$(date +'%Y-%m-%d %H:%M:%S')] $1\e[0m"
}

# Kiểm tra quyền sudo
if [[ $EUID -ne 0 ]]; then
  log "Cần quyền sudo để chạy script này."
  exit 1
fi

# Cập nhật hệ thống
log "Cập nhật hệ thống..."
apt update && apt upgrade -y

# Cài đặt các gói cần thiết
log "Cài đặt các gói cần thiết..."
apt install -y curl nginx nodejs npm pm2

# Cài đặt N8n
log "Cài đặt N8n..."
npm install -g n8n

# Cấu hình N8n service bằng systemd
log "Tạo cấu hình systemd cho N8n..."
cat << EOF | tee /etc/systemd/system/n8n.service
[Unit]
Description=N8N
After=network.target

[Service]
ExecStart=$(which n8n) start
Restart=always
User=$USER_NAME
Group=$USER_NAME  # Thêm group để tăng tính bảo mật

[Install]
WantedBy=multi-user.target
EOF

# Kích hoạt và khởi động N8n service
log "Kích hoạt và khởi động N8n service..."
systemctl enable n8n
systemctl start n8n

# Cấu hình Nginx
log "Tạo cấu hình Nginx cho N8n..."
cat << EOF | tee /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name localhost; # Thay đổi thành domain thật nếu có

    location / {
        proxy_pass http://localhost:${N8N_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Kích hoạt cấu hình Nginx
log "Kích hoạt cấu hình Nginx..."
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
nginx -t
systemctl restart nginx

log "N8n đã được cài đặt thành công!"
log "Truy cập http://localhost hoặc http://địa_chỉ_IP_của_bạn để sử dụng N8n"
