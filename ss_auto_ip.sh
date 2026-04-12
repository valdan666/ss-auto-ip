#!/bin/bash

# Скрипт установки и настройки Shadowsocks-libev
# Создаёт отдельный конфиг для каждого внешнего IP и объединяет все ссылки ss:// в один файл
# Подходит для серверов с несколькими IP, автоматически обновляется при повторном запуске

# Проверка установки Shadowsocks, при необходимости установка
if ! command -v ssserver &> /dev/null; then
  apt update
  apt install shadowsocks-libev -y
fi

config_dir="/etc/shadowsocks-libev"
mkdir -p "$config_dir"

# Определяем, куда сохранять файл ссылок
if [ -d "/var/www/html" ]; then
  links_file="/var/www/html/ss_links.txt"
  web_root="/var/www/html"
  server_type="nginx"
elif [ -d "/usr/share/nginx/html" ]; then
  links_file="/usr/share/nginx/html/ss_links.txt"
  web_root="/usr/share/nginx/html"
  server_type="nginx"
else
  links_file="/root/ss_links.txt"
  web_root="/root"
  server_type="python"
fi

# Если nginx отсутствует, устанавливаем
if [ "$server_type" = "nginx" ]; then
  if ! dpkg -s nginx &> /dev/null; then
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
  fi
fi

# Очищаем старые конфиги, если были
rm -f $config_dir/ss_*.json

# Очищаем файл ссылок
echo "" > "$links_file"

# Получаем список всех внешних IP
all_ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127|10\.|192\.168|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]')
base_port=8388
n=0

for ip in $all_ips; do
  port=$((base_port + n))
  password=$(openssl rand -hex 6)
  conf="$config_dir/ss_$port.json"

  # Создание отдельного конфига для IP
  cat > "$conf" <<EOF
{
    "server": "$ip",
    "server_port": $port,
    "password": "$password",
    "timeout": 300,
    "method": "aes-256-gcm",
    "fast_open": true,
    "no_delay": true
}
EOF

  # Генерация ss:// ссылки
  base64_str=$(echo -n "aes-256-gcm:$password@$ip:$port" | base64 -w 0 | tr -d '=')
  echo "ss://$base64_str#SS-$ip" >> "$links_file"

  n=$((n + 1))
done

# Создаём скрипт автозапуска всех конфигов
start_script="/usr/local/bin/ss_multi_start.sh"
echo "#!/bin/bash" > "$start_script"
echo "pkill ss-server 2>/dev/null" >> "$start_script"
for conf in $config_dir/ss_*.json; do
  echo "nohup ss-server -c $conf -u >/dev/null 2>&1 &" >> "$start_script"
done
chmod +x "$start_script"

# Запускаем все серверы
$start_script

# Настраиваем права на файл ссылок
chmod 644 "$links_file"

main_ip=$(hostname -I | awk '{print $1}')

echo
echo "Shadowsocks успешно настроен."
echo "Найдено IP: $(echo "$all_ips" | wc -l)"
echo "Файлы конфигурации: $config_dir/ss_*.json"
echo "Файл ссылок: $links_file"
echo
if [ "$server_type" = "nginx" ]; then
  echo "Скачай файл со всеми ссылками по адресу:"
  echo "http://$main_ip/ss_links.txt"
else
  echo "nginx не обнаружен, использую Python HTTP сервер:"
  echo "http://$main_ip:8000/ss_links.txt"
  echo "Чтобы завершить вручную — Ctrl+C"
  cd "$web_root" && python3 -m http.server 8000
fi

# Конец скрипта
