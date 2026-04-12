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

# Путь к файлу ссылок
links_file="/root/ss_links.txt"

# Очищаем старые конфиги и файл ссылок
rm -f $config_dir/ss_*.json
echo "" > "$links_file"

# Получаем список всех внешних IPv4, исключая внутренние диапазоны
all_ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127|10\.|192\.168|172\.(1[6-9]|2[0-9]|3[0-1])')

base_port=8388
n=0

# ANSI-коды для цветного вывода
GREEN="\033[32m"
RESET="\033[0m"

# Генерируем конфиги и ссылки
for ip in $all_ips; do
  port=$((base_port + n))
  password=$(openssl rand -hex 6)
  conf="$config_dir/ss_$port.json"

  # Создание отдельного конфига для каждого IP
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

  # Генерация ссылки ss://
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

# Вывод информации
echo
echo "Shadowsocks успешно настроен."
echo "Найдено IP: $(echo "$all_ips" | wc -l)"
echo "Файлы конфигурации сохранены в: $config_dir"
echo "Файл со всеми ссылками: $links_file"
echo

# Цветной вывод ссылок
echo -e "${GREEN}Ссылки для импорта в Nekobox:${RESET}"
cat "$links_file" | while read -r line; do
  echo -e "${GREEN}$line${RESET}"
done

echo
echo "Для перезапуска всех серверов вручную выполни:"
echo -e "${GREEN}/usr/local/bin/ss_multi_start.sh${RESET}"
echo
echo "Для автозапуска после перезагрузки добавь в cron:"
echo -e "${GREEN}@reboot /usr/local/bin/ss_multi_start.sh${RESET}"

# Конец скрипта
