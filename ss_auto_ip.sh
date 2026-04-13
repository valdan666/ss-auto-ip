#!/bin/bash
# bash <(curl -fsSL https://raw.githubusercontent.com/valdan666/ss-auto-ip/refs/heads/main/ss_auto_ip.sh)

# nano /etc/shadowsocks-libev/ss_8388.json
# cat /root/ss_links.txt

# Посмотреть содержимое директории можно командой:  
# ls -la /etc/shadowsocks-libev

# Если хочешь видеть только файлы конфигураций, то:  
# ls /etc/shadowsocks-libev/ss_*.json


# Скрипт установки и настройки Shadowsocks-libev
# При первом запуске устанавливает shadowsocks-libev
# При последующих — только проверяет и обновляет конфиги при изменении IP
# Создает новые конфиги для новых IP и удаляет старые для отсутствующих
# Если ничего не изменилось — просто выходит без действий

# Проверяем установлен ли Shadowsocks-libev
if ! command -v ss-server &> /dev/null; then
  echo -e "\033[96mShadowsocks-libev. Устанавливается...\033[0m"
  apt update -y
  apt install -y shadowsocks-libev jq openssl
#else
#  echo -e "\033[96mShadowsocks-libev уже установлен. Пропуск установки.\033[0m"
fi

# Папка для конфигов
config_dir="/etc/shadowsocks-libev"
mkdir -p "$config_dir"

# Файл ссылок
links_file="/root/ss_links.txt"

# Основной порт
base_port=8388

# Цвета
GREEN="\033[32m"
CYAN="\033[96m"
ORANGE="\e[38;5;51m"
RED="\033[31m"
RESET="\033[0m"

# Получаем список внешних IP
current_ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])')

# Считываем уже существующие конфиги
existing_confs=($(ls "$config_dir"/ss_*.json 2>/dev/null))
existing_ips=()
for conf in "${existing_confs[@]}"; do
  [ -f "$conf" ] && existing_ips+=($(jq -r '.server' "$conf"))
done

# Флаг изменения
ips_changed=0

# Определяем занятые порты (чтобы не пересекались)
used_ports=()
for conf in "${existing_confs[@]}"; do
  [ -f "$conf" ] && used_ports+=($(jq -r '.server_port' "$conf"))
done

# Добавляем новые IP, если нет в списке
for ip in $current_ips; do
  if ! printf '%s\n' "${existing_ips[@]}" | grep -qx "$ip"; then
    port=$base_port
    while printf '%s\n' "${used_ports[@]}" | grep -qx "$port"; do
      port=$((port + 1))
    done
    used_ports+=("$port")
    password=$(openssl rand -hex 6)
    conf="$config_dir/ss_${port}.json"
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
    ips_changed=1
    echo -e "${CYAN}new IP: $ip [$port]${RESET}"
  fi
done

# Удаляем конфиги для IP, которых больше нет
for conf in "${existing_confs[@]}"; do
  [ -f "$conf" ] || continue
  conf_ip=$(jq -r '.server' "$conf")
  if ! echo "$current_ips" | grep -qw "$conf_ip"; then
    rm -f "$conf"
    ips_changed=1
    echo -e "${RED}del IP: $conf_ip${RESET}"
  fi
done

# Если были изменения — обновляем файл ссылок и перезапускаем серверы
if [ $ips_changed -eq 1 ]; then
  echo -e "\n${ORANGE}update Shadowsocks | reboot server...${RESET}"
  
  echo "" > "$links_file"
  for conf in "$config_dir"/ss_*.json; do
    [ -f "$conf" ] || continue
    ip=$(jq -r '.server' "$conf")
    port=$(jq -r '.server_port' "$conf")
    password=$(jq -r '.password' "$conf")
    enc=$(echo -n "aes-256-gcm:$password@$ip:$port" | base64 -w 0 | tr -d '=')
    echo "ss://$enc#$ip" >> "$links_file"
  done

  start_script="/usr/local/bin/ss_multi_start.sh"
  echo "#!/bin/bash" > "$start_script"
  echo "sleep 20" >> "$start_script"
  echo "pkill ss-server 2>/dev/null" >> "$start_script"
  for conf in "$config_dir"/ss_*.json; do
    echo "nohup ss-server -c \"$conf\" -u >/dev/null 2>&1 &" >> "$start_script"
  done
  chmod +x "$start_script"
  $start_script
  chmod 644 "$links_file"

  #echo -e "\n${CYAN}Обновлены конфиги Shadowsocks и перезапущены серверы.${RESET}"
#else
#  echo -e "\n${CYAN}Изменений в IP или конфигурации нет, перезапуск не требуется.${RESET}"
fi

# Добавляем автозапуск в cron при первом запуске, если его нет
if ! crontab -l 2>/dev/null | grep -q "/usr/local/bin/ss_multi_start.sh"; then
  (crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/ss_multi_start.sh") | crontab -
  echo -e "${CYAN}Добавлен автозапуск Shadowsocks с отложенным стартом в cron.${RESET}"
fi

echo
echo -e "${ORANGE}Файлы конфигурации:${RESET} $config_dir"
echo -e "${CYAN}Файл ссылок:${RESET} $links_file"
echo
echo -e "\e[38;5;208mСсылки для импорта:${RESET}"
cat "$links_file" 2>/dev/null | while read -r line; do
  [ -n "$line" ] && echo -e "${CYAN}$line${RESET}"
done

#echo
#echo -e "${CYAN}Для ручного перезапуска всех серверов:${RESET}"
#echo -e "${GREEN}/usr/local/bin/ss_multi_start.sh${RESET}"
#echo
#echo -e "${CYAN}Для автозапуска после перезагрузки добавлен в cron:${RESET}"
#echo -e "${GREEN}@reboot /usr/local/bin/ss_multi_start.sh${RESET}"

# Конец скрипта
