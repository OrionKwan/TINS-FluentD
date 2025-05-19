#!/bin/bash
# Minimalist test for SNMPv3 trap reception

ID=$(date +%s)
echo "Sending basic SNMPv3 trap with ID: $ID"

# Send basic trap
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  192.168.8.100:1162 "" 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.5.0 s "TEST-$ID"

echo "Trap sent. Waiting 3 seconds..."
sleep 3

echo "Checking logs for trap receipt:"
docker exec fluentd-snmp-trap bash -c 'tail -5 /var/log/snmptrapd.log' 