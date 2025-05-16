#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

line_skip()   { echo -e ". . ."; }
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration file paths
CLIENT_CONFIG="./openvpn/client.ovpn"
SERVER_CONFIG="./openvpn/server.conf"

# Create temp files for route definitions
CLIENT_ROUTES_TMP=$(mktemp)
SERVER_ROUTES_TMP=$(mktemp)

# Add comments to the top of the route sections
echo "# Discord routes - Generated $(date)" > "$CLIENT_ROUTES_TMP"
echo "# Discord routes - Generated $(date)" > "$SERVER_ROUTES_TMP"

log_info "Counting files for progress tracking..."

# Count total lines for progress tracking
total_lines=0

# Count lines in region files
for region_dir in regions/*; do
    region_name=$(basename "$region_dir")
    input_file="${region_dir}/${region_name}-voice-resolved"
    if [[ -f "$input_file" ]]; then
        lines_in_file=$(wc -l < "$input_file")
        total_lines=$((total_lines + lines_in_file))
    fi
done

# Count lines in main_domains files
if [[ -d "main_domains" ]]; then
    # Count discord-main-ip-list 
    if [[ -f "main_domains/discord-main-ip-list" ]]; then
        lines_in_file=$(grep -v "^$" "main_domains/discord-main-ip-list" | wc -l)
        total_lines=$((total_lines + lines_in_file))
    fi
    
    # Count any resolved files
    for domain_file in main_domains/*-resolved; do
        if [[ -f "$domain_file" && ! "$domain_file" == *"ipset-list"* ]]; then
            lines_in_file=$(wc -l < "$domain_file")
            total_lines=$((total_lines + lines_in_file))
        fi
    done
fi

processed_lines=0

process_region() {
    local region_dir="$1"
    local region_name
    region_name=$(basename "$region_dir")
    local input_file="${region_dir}/${region_name}-voice-resolved"
    
    if [[ ! -f "$input_file" ]]; then
        log_warn "${RED}${input_file}${NC} не найден – пропускаем регион ${MAGENTA}$region_name${NC}"
        line_skip
        return
    fi
    
    log_info "Обрабатываем регион: ${MAGENTA}$region_name${NC}"
    
    # Add region header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Region: $region_name" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Region: $region_name" >> "$SERVER_ROUTES_TMP"
    
    while IFS=':' read -r hostname ip; do
        hostname=$(echo "$hostname" | xargs)
        ip=$(echo "$ip" | xargs)
        [[ -z "$hostname" || -z "$ip" ]] && continue
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$input_file"
    
    log_success "Регион ${MAGENTA}$region_name${NC} успешно обработан!"
    line_skip
}

process_main_domain() {
    local domain_file="$1"
    local domain_name
    domain_name=$(basename "$domain_file" | sed 's/-resolved//')
    
    if [[ ! -f "$domain_file" ]]; then
        log_warn "${RED}${domain_file}${NC} не найден – пропускаем домен ${MAGENTA}$domain_name${NC}"
        line_skip
        return
    fi
    
    log_info "Обрабатываем домен: ${MAGENTA}$domain_name${NC}"
    
    # Add domain header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Main Domain: $domain_name" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Main Domain: $domain_name" >> "$SERVER_ROUTES_TMP"
    
    while IFS=':' read -r hostname ip; do
        hostname=$(echo "$hostname" | xargs)
        ip=$(echo "$ip" | xargs)
        [[ -z "$hostname" || -z "$ip" ]] && continue
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$domain_file"
    
    log_success "Домен ${MAGENTA}$domain_name${NC} успешно обработан!"
    line_skip
}

process_main_ip_list() {
    local ip_file="$1"
    
    if [[ ! -f "$ip_file" ]]; then
        log_warn "${RED}${ip_file}${NC} не найден!"
        line_skip
        return
    fi
    
    log_info "Обрабатываем основные IP Discord..."
    
    # Add domain header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Main Discord IPs" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Main Discord IPs" >> "$SERVER_ROUTES_TMP"
    
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        
        # Get clean IP
        ip=$(echo "$ip" | xargs)
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$ip_file"
    
    log_success "Основные IP Discord успешно обработаны!"
    line_skip
}

log_info "Обрабатываем региональные голосовые серверы..."
for region_dir in regions/*; do
    if [[ -d "$region_dir" ]]; then
        process_region "$region_dir"
    fi
done

log_info "Обрабатываем основные домены Discord..."
if [[ -d "main_domains" ]]; then
    # Process the discord-main-ip-list file (contains only IPs)
    if [[ -f "main_domains/discord-main-ip-list" ]]; then
        process_main_ip_list "main_domains/discord-main-ip-list"
    else
        log_warn "Файл discord-main-ip-list не найден!"
    fi
    
    # Process any other resolved files (excluding the ipset-list)
    for domain_file in main_domains/*-resolved; do
        if [[ -f "$domain_file" && ! "$domain_file" == *"ipset-list"* ]]; then
            process_main_domain "$domain_file"
        fi
    done
else
    log_warn "Директория main_domains не найдена!"
fi

log_info "Обновляем конфигурационные файлы OpenVPN..."

# Create backup of original files
cp "$CLIENT_CONFIG" "${CLIENT_CONFIG}.bak"
cp "$SERVER_CONFIG" "${SERVER_CONFIG}.bak"

# Update client config
awk -v routes="$(cat $CLIENT_ROUTES_TMP)" '
/# BEGIN_DISCORD_ROUTES/{print; print routes; next}
/# END_DISCORD_ROUTES/{print; next}
/# Discord routes/{next}
/(^route |IP-ADRESSES)/{next} 
{print}' "${CLIENT_CONFIG}.bak" > "$CLIENT_CONFIG"

# Update server config
awk -v routes="$(cat $SERVER_ROUTES_TMP)" '
/# BEGIN_DISCORD_ROUTES/{print; print routes; next}
/# END_DISCORD_ROUTES/{print; next}
/# Discord routes/{next}
/^push "route /{next}
{print}' "${SERVER_CONFIG}.bak" > "$SERVER_CONFIG"

# Clean up temp files
rm "$CLIENT_ROUTES_TMP" "$SERVER_ROUTES_TMP"

log_success "Готово! Конфигурационные файлы OpenVPN обновлены маршрутами Discord серверов."
log_info "Резервные копии сохранены как ${CLIENT_CONFIG}.bak и ${SERVER_CONFIG}.bak"