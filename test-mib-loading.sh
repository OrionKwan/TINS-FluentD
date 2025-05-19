#!/bin/bash
# Script to test if the MIB files are properly loaded in the fluentd-snmp container

# Colors for better output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Testing MIB Loading in fluentd-snmp container ===${NC}"

# 1. First ensure the container is running
echo -e "${BLUE}1. Checking container status...${NC}"
container_running=$(docker ps -q -f name=fluentd-snmp-trap)

if [ -z "$container_running" ]; then
  echo -e "${YELLOW}Container is not running. Starting it...${NC}"
  docker start fluentd-snmp-trap
  sleep 5
  
  # Check again
  if ! docker ps -q -f name=fluentd-snmp-trap > /dev/null; then
    echo -e "${RED}Failed to start container. Check logs for details.${NC}"
    docker logs fluentd-snmp-trap | tail -20
    exit 1
  fi
  echo -e "${GREEN}Container started successfully.${NC}"
else
  echo -e "${GREEN}Container is already running.${NC}"
fi

# 2. Check if MIB files are loaded
echo -e "\n${BLUE}2. Checking if MIB files are loaded...${NC}"
mib_files=$(docker exec fluentd-snmp-trap ls -la /usr/share/snmp/mibs/ | grep -E "HW-|IMAP_")

if [ -n "$mib_files" ]; then
  echo -e "${GREEN}MIB files found in the container:${NC}"
  echo "$mib_files"
else
  echo -e "${RED}No MIB files found! They may not have been copied correctly.${NC}"
  echo "Contents of MIB directory:"
  docker exec fluentd-snmp-trap ls -la /usr/share/snmp/mibs/
  exit 1
fi

# 3. Check if snmptrapd is running
echo -e "\n${BLUE}3. Checking if snmptrapd is running...${NC}"
if docker exec fluentd-snmp-trap pgrep snmptrapd > /dev/null; then
  echo -e "${GREEN}snmptrapd is running in the container.${NC}"
else
  echo -e "${RED}snmptrapd is NOT running in the container!${NC}"
  echo "Starting snmptrapd manually..."
  docker exec fluentd-snmp-trap sh -c "snmptrapd -c /etc/snmp/snmptrapd.conf -Lf /var/log/snmptrapd.log -p /var/run/snmptrapd.pid -f &"
  sleep 2
  
  if docker exec fluentd-snmp-trap pgrep snmptrapd > /dev/null; then
    echo -e "${GREEN}snmptrapd started successfully.${NC}"
  else
    echo -e "${RED}Failed to start snmptrapd.${NC}"
    exit 1
  fi
fi

# 4. Send a test trap
echo -e "\n${BLUE}4. Sending a test SNMPv3 trap...${NC}"
TRAP_ID="MIB-TEST-$(date +%s)"
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)

echo "Trap ID: $TRAP_ID"
echo "Container IP: $CONTAINER_IP"

# Create the SNMP command using Huawei MIB OIDs referenced in the new MIBs
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv "$CONTAINER_IP:1162" '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.0 s "Test NE Name" \
  1.3.6.1.4.1.2011.2.15.1.7.1.2.0 s "Test NE Type" \
  1.3.6.1.4.1.2011.2.15.1.7.1.3.0 s "$TRAP_ID" 2>/dev/null

echo -e "${GREEN}Trap sent. Waiting for processing...${NC}"
sleep 3

# 5. Check if trap was received and processed
echo -e "\n${BLUE}5. Checking if trap was received...${NC}"
if docker exec fluentd-snmp-trap grep -q "$TRAP_ID" /var/log/snmptrapd.log; then
  echo -e "${GREEN}Trap was received successfully!${NC}"
  echo "Trap log entry:"
  docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log
  
  # Check if MIB names were resolved (instead of showing numeric OIDs)
  if docker exec fluentd-snmp-trap grep -q "HW-IMAPV1NORTHBOUND-TRAP-MIB" /var/log/snmptrapd.log || \
     docker exec fluentd-snmp-trap grep -q "IMAP_NORTHBOUND_MIB" /var/log/snmptrapd.log; then
    echo -e "${GREEN}MIB names were resolved correctly! The MIB files are working.${NC}"
  else
    echo -e "${YELLOW}Trap was received but MIB names weren't resolved to readable form.${NC}"
    echo "This may indicate the MIB files aren't being correctly loaded or parsed."
  fi
else
  echo -e "${RED}Trap was NOT received or wasn't logged!${NC}"
  echo "Recent log entries:"
  docker exec fluentd-snmp-trap tail -20 /var/log/snmptrapd.log
fi

echo -e "\n${BLUE}Test completed.${NC}" 