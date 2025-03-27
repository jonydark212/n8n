#!/bin/bash

# Hiển thị logo PAGE1.VN
show_logo() {
  echo -e "\e[1;36m"
  echo "  ____    _    ____ _____ _ __     ___   _ "
  echo " |  _ \  / \  / ___| ____/ |  \   / / \ | |"
  echo " | |_) |/ _ \| |  _|  _| | |   \ / / _ \| |"
  echo " |  __/ / ___ \ |_| | |___| |    V / ___ \ |"
  echo " |_|  /_/   \_\____|_____|_|    /_/_/   \_\_|"
  echo -e "\e[0m"
}

# Hiển thị logo khi bắt đầu
show_logo

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

# Danh sách các gói cần thiết
REQUIRED_PACKAGES="curl nginx build-essential python3 git"

# Hàm để hiển thị thông báo và ghi log
log() {
  echo -e "\e[1m[$(date +'%Y-%m-%d %H:%M:%S')] $1\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Hàm kiểm tra và cài đặt gói nếu chưa có
install_package() {
  if ! dpkg -l | grep -q "$1"; then
    log "Cài đặt gói $1..."
    sudo apt install -y "$1" || {
      log "Không thể cài đặt gói $1. Thử lại..."
      sudo apt update
      sudo apt install -y "$1" || {
        log "Không thể cài đặt gói $1 sau khi cập nhật. Kiểm tra kết nối mạng."
        return 1
      }
    }
    log "Đã cài đặt gói $1 thành công."
  else
    log "Gói $1 đã được cài đặt."
  fi
  return 0
}

# Hàm kiểm tra và thêm sudo nếu cần thiết
run_with_sudo() {
  if command -v sudo &> /dev/null; then
    sudo "$@"
  else
    "$@"
  fi
}

# Kiểm tra và cài đặt sudo nếu cần
if [[ $EUID -ne 0 ]]; then
  log "Script không chạy với quyền root. Kiểm tra sudo..."
  if ! command -v sudo &> /dev/null; then
    log "Sudo chưa được cài đặt. Đang cài đặt sudo..."
    apt update && apt install -y sudo || {
      log "Không thể cài đặt sudo. Vui lòng chạy script với quyền root hoặc cài đặt sudo trước."
      exit 1
    }
    log "Đã cài đặt sudo thành công."
  fi
  
  # Kiểm tra xem người dùng hiện tại có trong nhóm sudo không
  if ! groups "$USER_NAME" | grep -q sudo; then
    log "Thêm người dùng $USER_NAME vào nhóm sudo..."
    usermod -aG sudo "$USER_NAME" || {
      log "Không thể thêm người dùng vào nhóm sudo. Vui lòng chạy script với quyền root."
      exit 1
    }
    log "Đã thêm người dùng vào nhóm sudo. Vui lòng đăng xuất và đăng nhập lại, sau đó chạy lại script."
    exit 0
  fi
  
  log "Chạy lại script với sudo..."
  exec sudo "$0" "$@"
  exit $?
fi

# Kiểm tra hệ điều hành
if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
  log "Script này chỉ hỗ trợ Ubuntu hoặc Debian."
  exit 1
fi

# Cập nhật hệ thống
log "Cập nhật hệ thống..."
sudo apt update || {
  log "Không thể cập nhật danh sách gói. Thử lại sau 5 giây..."
  sleep 5
  sudo apt update || {
    log "Không thể cập nhật danh sách gói. Kiểm tra kết nối mạng và thử lại."
    exit 1
  }
}

log "Nâng cấp các gói đã cài đặt..."
sudo apt upgrade -y || {
  log "Không thể nâng cấp hệ thống. Thử lại sau 5 giây..."
  sleep 5
  sudo apt upgrade -y || {
    log "Cảnh báo: Không thể nâng cấp hệ thống. Tiếp tục cài đặt..."
  }
}

# Cài đặt các gói cần thiết
log "Kiểm tra và cài đặt các gói cần thiết..."
for package in $REQUIRED_PACKAGES; do
  install_package "$package" || {
    log "Cảnh báo: Không thể cài đặt gói $package. Tiếp tục cài đặt..."
  }
done

# Kiểm tra và cài đặt Node.js phiên bản phù hợp
log "Kiểm tra phiên bản Node.js..."
if ! command -v node &> /dev/null || [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt 18 ]]; then
  log "Cài đặt Node.js ${NODE_VERSION}..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo bash - || {
    log "Không thể thiết lập kho lưu trữ Node.js. Thử lại..."
    sleep 5
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo bash - || {
      log "Không thể thiết lập kho lưu trữ Node.js. Kiểm tra kết nối mạng."
      exit 1
    }
  }
  sudo apt install -y nodejs || {
    log "Không thể cài đặt Node.js. Thử lại..."
    sudo apt update
    sudo apt install -y nodejs || {
      log "Không thể cài đặt Node.js. Kiểm tra kết nối mạng."
      exit 1
    }
  }
fi

# Kiểm tra phiên bản Node.js sau khi cài đặt
NODE_CURRENT=$(node -v)
log "Phiên bản Node.js hiện tại: ${NODE_CURRENT}"

# Cài đặt npm và pm2
log "Kiểm tra và cài đặt npm..."
if ! command -v npm &> /dev/null; then
  log "Cài đặt npm..."
  sudo apt install -y npm || {
    log "Không thể cài đặt npm. Thử lại..."
    sudo apt update
    sudo apt install -y npm || {
      log "Không thể cài đặt npm. Kiểm tra kết nối mạng."
      exit 1
    }
  }
fi

log "Kiểm tra và cài đặt pm2..."
if ! command -v pm2 &> /dev/null; then
  log "Cài đặt pm2 toàn cục..."
  sudo npm install -g pm2 || {
    log "Không thể cài đặt pm2 qua npm. Thử lại..."
    sudo npm cache clean -f
    sudo npm install -g pm2 || {
      log "Không thể cài đặt pm2. Kiểm tra kết nối mạng."
      exit 1
    }
  }
fi

# Kiểm tra kết nối mạng trước khi cài đặt N8n
log "Kiểm tra kết nối mạng..."
if ! ping -c 1 registry.npmjs.org &> /dev/null; then
  log "Không thể kết nối đến registry.npmjs.org. Kiểm tra kết nối mạng của bạn."
  exit 1
fi

# Cài đặt N8n với timeout và retry
log "Cài đặt N8n..."
MAX_RETRIES=3
RETRY_COUNT=0
TIMEOUT=300  # 5 phút timeout

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Xóa cache npm trước mỗi lần thử
  if [ $RETRY_COUNT -gt 0 ]; then
    log "Xóa cache npm và thử lại (lần thử ${RETRY_COUNT}/${MAX_RETRIES})..."
    sudo npm cache clean -f
    sleep 5
  fi

  # Sử dụng timeout để tránh treo
  timeout $TIMEOUT sudo npm install -g n8n || {
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
      log "Không thể cài đặt N8n sau ${MAX_RETRIES} lần thử. Lỗi có thể do:"
      log "  - Kết nối mạng không ổn định"
      log "  - Registry npm không phản hồi"
      log "  - Không đủ dung lượng ổ đĩa"
      log "  - Lỗi phân quyền"
      log "Vui lòng kiểm tra các vấn đề trên và thử lại."
      exit 1
    fi
    continue
  }
  break
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
  sudo mkdir -p "$N8N_CONFIG_DIR"
  sudo chown -R ${USER_NAME}:${USER_NAME} "$N8N_CONFIG_DIR"
fi

# Cấu hình N8n service bằng systemd
log "Tạo cấu hình systemd cho N8n..."
cat << EOF | sudo tee /etc/systemd/system/n8n.service
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
sudo systemctl daemon-reload
sudo systemctl enable n8n
sudo systemctl start n8n || {
  log "Không thể khởi động N8n service. Kiểm tra lỗi với: systemctl status n8n"
  sudo systemctl status n8n
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
sudo ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n

# Kiểm tra cấu hình Nginx
if ! sudo nginx -t; then
  log "Cấu hình Nginx không hợp lệ. Vui lòng kiểm tra lại."
  exit 1
fi

# Khởi động lại Nginx
sudo systemctl restart nginx || {
  log "Không thể khởi động lại Nginx. Kiểm tra lỗi với: systemctl status nginx"
  sudo systemctl status nginx
  exit 1
}

# Kiểm tra kết nối đến N8n
log "Kiểm tra kết nối đến N8n..."
sleep 5
if ! curl -s --head http://localhost | grep "200 OK" > /dev/null; then
  log "Cảnh báo: Không thể kết nối đến N8n qua Nginx. Kiểm tra lại cấu hình."
  log "Bạn có thể cần kiểm tra trạng thái N8n và Nginx:"
  log "  - sudo systemctl status n8n"
  log "  - sudo systemctl status nginx"
  log "  - curl -v http://localhost:${N8N_PORT}"
  
  # Thử khởi động lại dịch vụ
  log "Thử khởi động lại dịch vụ N8n và Nginx..."
  sudo systemctl restart n8n
  sudo systemctl restart nginx
  
  # Kiểm tra lại kết nối
  sleep 5
  if ! curl -s --head http://localhost | grep "200 OK" > /dev/null; then
    log "Vẫn không thể kết nối. Vui lòng kiểm tra cấu hình thủ công."
  else
    log "Kết nối thành công sau khi khởi động lại dịch vụ."
  fi
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

log "Cài đặt hoàn tất. Để quản lý dịch vụ N8n, sử dụng các lệnh:"
log "  - Khởi động: sudo systemctl start n8n"
log "  - Dừng: sudo systemctl stop n8n"
log "  - Khởi động lại: sudo systemctl restart n8n"
log "  - Kiểm tra trạng thái: sudo systemctl status n8n"
