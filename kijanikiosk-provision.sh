#!/bin/bash

# ==============================================================================
# PHASE 1: PRE-PROVISIONING AUDIT COMMENTS
# ==============================================================================
# EXPECTED DIRTY CONDITIONS FOUND IN PRE-PROVISIONING AUDIT:
# - kk-api already exists (UID 998): handled via user check and conditional creation
# - /opt/kijanikiosk/shared/logs ACLs missing entry: fixed via explicit setfacl
# - ufw has extra deny 3001 rule from Thursday: reset and cleanly rebuilt in firewall phase
# ==============================================================================

# Exit immediately if any command fails
set -e

# ==============================================================================
# PHASE 2: USER, GROUP, AND DIRECTORY PROVISIONING
# ==============================================================================
echo "Configuring application groups, users, and directories..."

# 1. Create the primary group first
if ! getent group kijanikiosk >/dev/null; then
    sudo groupadd kijanikiosk
fi

# 2. Create the restricted system users
for user in kk-api kk-payments kk-logs; do
    if ! getent passwd $user >/dev/null; then
        sudo useradd -r -g kijanikiosk -s /usr/sbin/nologin $user
    fi
done

# 3. Create the directories safely
sudo mkdir -p /opt/kijanikiosk/shared/logs
sudo mkdir -p /opt/kijanikiosk/config
sudo mkdir -p /opt/kijanikiosk/health

# Create the environment file required by your systemd configuration spec
sudo touch /opt/kijanikiosk/config/payments-api.env
echo "PORT=3001" | sudo tee /opt/kijanikiosk/config/payments-api.env > /dev/null

# 4. Set ownership cleanly
sudo chown -R root:kijanikiosk /opt/kijanikiosk
sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/health
sudo chown kk-payments:kijanikiosk /opt/kijanikiosk/config/payments-api.env
sudo chmod 640 /opt/kijanikiosk/config/payments-api.env

# 5. Apply the Access Control Lists (ACLs)
sudo chmod 2775 /opt/kijanikiosk/shared/logs
sudo setfacl -b /opt/kijanikiosk/shared/logs
sudo setfacl -d -m g:kijanikiosk:rwX /opt/kijanikiosk/shared/logs
sudo setfacl -m u:kk-api:rwx /opt/kijanikiosk/shared/logs
sudo setfacl -m u:kk-payments:rwx /opt/kijanikiosk/shared/logs

echo "Directory structures, environment files, and ACL settings finalized!"

# ==============================================================================
# PHASE 3: SYSTEMD SERVICE PROVISIONING & HARDENING
# ==============================================================================
echo "Deploying and hardening the systemd payments service..."

sudo tee /etc/systemd/system/kk-payments.service > /dev/null << 'EOF'
[Unit]
Description=KijaniKiosk Payments Production Engine
After=network.target

[Service]
Type=simple
User=kk-payments
Group=kijanikiosk
ExecStart=/usr/bin/python3 -m http.server 3001
Restart=on-failure

ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
CapabilityBoundingSet=
RestrictNamespaces=true
MemoryDenyWriteExecute=true
PrivateDevices=true
ProtectClock=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictSUIDSGID=true
LockPersonality=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
DynamicUser=yes
PrivateUsers=yes
PrivateNetwork=yes

SystemCallFilter=@system-service
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

ReadOnlyPaths=/
ReadWritePaths=/var/lib/kk-payments
RestrictRealtime=true
UMask=0077
RemoveIPC=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable kk-payments.service
sudo systemctl restart kk-payments.service

# ==============================================================================
# Phase 4: UFW Firewall Policies
# ==============================================================================
echo "=== Phase 4: Configuring UFW Firewall Policies ==="

# 1. Reset UFW to a known clean baseline
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 2. Apply rules with board-presentable comments
# CRITICAL ORDERING: Allow loopback on 3001 BEFORE denying it externally
sudo ufw allow in on lo to any port 3001 comment 'Allow nginx proxying to payments service via loopback'
sudo ufw deny proto tcp from any to any port 3001 comment 'Explicitly deny external sources from port 3001'

# Restrict management and web access to the monitoring subnet
sudo ufw allow from 10.0.1.0/24 to any port 22 proto tcp comment 'Allow SSH from monitoring subnet only'
sudo ufw allow from 10.0.1.0/24 to any port 80 proto tcp comment 'Allow HTTP from monitoring subnet only'

# Enable the firewall
sudo ufw --force enable

# ==============================================================================
# Phase 4 Verification: Evaluating Firewall Intent Programmatically
# ==============================================================================
echo "=== Verification: Evaluating Firewall Intent ==="

verify_rule_flexible() {
    local target_port="$1"
    local action="$2"
    local source_or_interface="$3"
    local description="$4"
    
    # Capture the output of ufw status numbered once per check
    local ufw_dump
    ufw_dump=$(sudo ufw status numbered)
    
    # Pipeline independent filters to avoid strict spacing issues
    if echo "$ufw_dump" | grep -i "$target_port" | grep -i "$action" | grep -F "$source_or_interface" > /dev/null; then
        echo "PASS: $description"
    else
        echo "FAIL: $description"
    fi
}

# Execute the decoupling checks
verify_rule_flexible "3001" "ALLOW" "on lo" "Loopback allowed on port 3001"
verify_rule_flexible "3001" "DENY" "Anywhere" "External access denied on port 3001"
verify_rule_flexible "22" "ALLOW" "10.0.1.0/24" "SSH restricted to monitoring subnet"
verify_rule_flexible "80" "ALLOW" "10.0.1.0/24" "HTTP restricted to monitoring subnet"
# ==============================================================================
# PHASE 5: ADDITIONAL SYSTEMD SERVICES
# ==============================================================================
echo "Deploying kk-api and kk-logs services..."

sudo touch /opt/kijanikiosk/config/api.env
echo "PORT=3000" | sudo tee /opt/kijanikiosk/config/api.env >/dev/null

sudo touch /opt/kijanikiosk/config/logs.env
echo "LOG_LEVEL=INFO" | sudo tee /opt/kijanikiosk/config/logs.env >/dev/null

sudo chown kk-api:kijanikiosk /opt/kijanikiosk/config/api.env
sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/config/logs.env

sudo chmod 640 /opt/kijanikiosk/config/api.env
sudo chmod 640 /opt/kijanikiosk/config/logs.env

sudo tee /etc/systemd/system/kk-api.service >/dev/null << 'EOF'
[Unit]
Description=KijaniKiosk API Service
After=network.target

[Service]
Type=simple
User=kk-api
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/api.env
ExecStart=/usr/bin/python3 -m http.server 3000

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/kk-logs.service >/dev/null << 'EOF'
[Unit]
Description=KijaniKiosk Log Monitor
After=network.target

[Service]
Type=simple
User=kk-logs
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/logs.env
ExecStart=/usr/bin/tail -F /opt/kijanikiosk/shared/logs/app.log

Restart=always

PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable kk-api.service
sudo systemctl enable kk-logs.service

sudo systemctl restart kk-api.service
sudo systemctl restart kk-logs.service

# ==============================================================================
# PHASE 6: JOURNAL PERSISTENCE
# ==============================================================================
echo "Configuring persistent journald storage..."

sudo mkdir -p /var/log/journal

sudo tee /etc/systemd/journald.conf >/dev/null <<EOF
[Journal]
Storage=persistent
SystemMaxUse=500M
EOF

sudo systemctl restart systemd-journald

# ==============================================================================
# PHASE 7: LOGROTATE CONFIGURATION
# ==============================================================================
echo "Configuring log rotation..."

sudo tee /etc/logrotate.d/kijanikiosk >/dev/null <<EOF
/opt/kijanikiosk/shared/logs/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 640 kk-api kijanikiosk
    postrotate
        systemctl restart kk-logs.service >/dev/null 2>&1 || true
    endscript
}
EOF

# ==============================================================================
# PHASE 8: MONITORING HEALTH CHECKS
# ==============================================================================
echo "Running network port and health validation..."

api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null && echo "ok" || echo "down")
payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null && echo "ok" || echo "down")

mkdir -p /opt/kijanikiosk/health

echo "{\"timestamp\":\"$(date -Is)\",\"kk-api\":\"$api_status\",\"kk-payments\":\"$payments_status\"}" | sudo tee /opt/kijanikiosk/health/last-provision.json > /dev/null

sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/health/last-provision.json
sudo chmod 640 /opt/kijanikiosk/health/last-provision.json

FAILED=0

systemctl is-enabled kk-api.service >/dev/null \
 && echo "PASS: kk-api enabled" \
 || FAILED=1

systemctl is-enabled kk-payments.service >/dev/null \
 && echo "PASS: kk-payments enabled" \
 || FAILED=1

systemctl is-enabled kk-logs.service >/dev/null \
 && echo "PASS: kk-logs enabled" \
 || FAILED=1

test -f /etc/logrotate.d/kijanikiosk \
 && echo "PASS: logrotate config exists" \
 || FAILED=1

test -f /opt/kijanikiosk/health/last-provision.json \
 && echo "PASS: health file exists" \
 || FAILED=1

if [ "$FAILED" -ne 0 ]; then
    echo "Provisioning verification failed."
    exit 1
fi

echo "All verification checks passed."
exit 0
