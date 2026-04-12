#!/bin/bash

# Скрипт автоматической установки и настройки Shadowsocks
# Создаёт конфигурационный файл для всех внешних IP и файл ссылок ss:// для импорта в клиент

# Проверка установки Shadowsocks, при необходимости установка
if ! command -v ssserver &> /dev/null; then
  apt update
  apt install shadowsocks-libev -y
fi

config_dir="/etc/shadowsocks-libev"
config_file="${config_dir}/config.json"

# ----- Определяем, куда сохранить файл ссылок -----
# Проверяем наличие каталогов по умолчанию для nginx
if [ -d "/var/www/html" ]; then
  links_file="/var/www/html/ss_links.txt"
  web_root="/var/www/html"
  server_type="nginx"
elif [ -d "/usr/share/nginx/html" ]; then
  links_file="/usr/share/nginx/html/ss_links.txt"
  web_root="/usr/share/nginx/html"
  server_type="nginx"
else
  # если nginx нет — сохраняем в /root и будем раздавать через встроенный сервер Python
  links_file="/root/ss_links.txt"
  web_root="/root"
  server_type="python"
fi

# Создание каталога конфигурации
mkdir -p $config_dir

# Установка nginx при его отсутствии
if [ "$server_type" = "nginx" ]; then
  if ! dpkg -s nginx &> /dev/null; then
    apt install nginx -y
    systemctl enable nginx
    systemctl start nginx
  fi
fi

# Получаем все внешние IPv4 (исключаем внутренние сети)
all_ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127|10\.|192\.168|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]')

# Начальный порт для первого сервера
base_port=8388

# Начинаем создание JSON для Shadowsocks
echo "[" > $config_file
# Создаём или очищаем файл для ссылок
echo "" > $links_file

n=0
total=$(echo "$all_ips" | wc -l)

# Перебор всех найденных IP, генерация настроек и ссылок
for ip in $all_ips; do
  port=$((base_port + n))
  password=$(openssl rand -hex 6)
  
  # Запись блока в config.json
  echo "  {" >> $config_file
  echo "    \"server\": \"$ip\"," >> $config_file
  echo "    \"server_port\": $port," >> $config_file
  echo "    \"password\": \"$password\"," >> $config_file
  echo "    \"timeout\": 300," >> $config_file
  echo "    \"method\": \"aes-256-gcm\"" >> $config_file
  
  n=$((n + 1))
  
  # Добавляем запятую, если это не последний элемент
  if [ $n -lt $total ]; then
    echo "  }," >> $config_file
  else
    echo "  }" >> $config_file
  fi

  # Генерация ss:// ссылки в формате base64
  base64_str=$(echo -n "aes-256-gcm:$password@$ip:$port" | base64 -w 0 | tr -d '=')
  echo "ss://$base64_str#SS-$ip" >> $links_file
done

# Завершаем JSON
echo "]" >> $config_file

# Перезапускаем Shadowsocks для применения настроек
systemctl restart shadowsocks-libev.service

# Настраиваем права доступа к файлу ссылок
chmod 644 $links_file

# Определяем IP основного интерфейса
main_ip=$(hostname -I | awk '{print $1}')

echo
echo "Shadowsocks настроен успешно."
echo "Файл конфигурации: $config_file"
echo "Файл ссылок: $links_file"
echo

# Проверяем тип сервера и выводим соответствующую ссылку
if [ "$server_type" = "nginx" ]; then
  echo "Можно скачать файл ссылок по адресу:"
  echo "http://$main_ip/ss_links.txt"
else
  echo "nginx не установлен — используем встроенный Python HTTP-сервер."
  echo "Запущен временный сервер на порту 8000."
  echo "Файл доступен по адресу:"
  echo "http://$main_ip:8000/ss_links.txt"
  echo "Чтобы завершить сервер — нажми Ctrl+C."
  cd $web_root && python3 -m http.server 8000
fi

# Конец скрипта
