#!/bin/bash

# Устанавливаем Shadowsocks, если не установлен
if ! command -v ssserver &> /dev/null; then
  apt update
  apt install shadowsocks-libev -y
fi

config_dir="/etc/shadowsocks-libev"
config_file="${config_dir}/config.json"

mkdir -p $config_dir

# Узнаем все внешние IPv4
all_ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127|10\.|192\.168|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]')

# Начальный порт
base_port=8388

# Начало JSON
echo "[" > $config_file

n=0
for ip in $all_ips; do
  port=$((base_port + n))
  password=$(openssl rand -hex 6)
  
  echo "  {" >> $config_file
  echo "    \"server\": \"$ip\"," >> $config_file
  echo "    \"server_port\": $port," >> $config_file
  echo "    \"password\": \"$password\"," >> $config_file
  echo "    \"timeout\": 300," >> $config_file
  echo "    \"method\": \"aes-256-gcm\"" >> $config_file
  
  n=$((n + 1))
  
  if [ $n -lt $(echo "$all_ips" | wc -l) ]; then
    echo "  }," >> $config_file
  else
    echo "  }" >> $config_file
  fi
done

# Конец JSON
echo "]" >> $config_file

systemctl restart shadowsocks-libev.service

echo "Shadowsocks сконфигурирован для IP:"
echo "$all_ips"
echo "Файл настроек: $config_file"
