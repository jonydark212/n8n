#!/bin/bash

# Cập nhật hệ thống
sudo apt update && sudo apt upgrade -y

# Cài đặt Node.js và npm
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Cài đặt N8n
sudo npm install -g n8n

# Cài đặt PM2 để quản lý tiến trình
sudo npm install -g pm2

# Tạo file cấu hình systemd cho N8n
cat << EOF | sudo tee /etc/systemd/system/n8n.service
[Unit]
Description=N8N
After=network.target

[Service]
ExecStart=$(which n8n) start
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

# Kích hoạt và khởi động N8n service
sudo systemctl enable n8n
sudo systemctl start n8n

# Cài đặt Nginx
sudo apt install -y nginx

# Tạo cấu hình Nginx cho N8n
cat << EOF | sudo tee /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# Kích hoạt cấu hình Nginx
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

echo "N8n đã được cài đặt thành công!"
echo "Truy cập http://localhost hoặc http://địa_chỉ_IP_của_bạn để sử dụng N8n"
