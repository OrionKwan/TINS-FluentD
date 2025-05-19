# SNMP Plugin Flow Diagram

```mermaid
graph TD
    A[External SNMP Traps] -->|UDP port 1162| B[SNMPTRAPD]
    B1[SNMPv3 User: NCEadmin] -->|Auth SHA| B
    B2[SNMPv2c Community: public] --> B
    B -->|Writes to| C[/var/log/snmptrapd.log]
    C -->|Read by tail plugin| D[Fluentd tail source]
    D -->|Parse regex| E[Regexp parser filter]
    E -->|Extract data| F[Record transformer filter]
    F -->|Copy plugin| G[Multiple outputs]
    G -->|Store 1| H[Stdout for debugging]
    G -->|Store 2| I[Remote Syslog output]
    I -->|UDP| J[UDP Forward to target host]
    J -->|Forward traps| K[External Systems]
``` 