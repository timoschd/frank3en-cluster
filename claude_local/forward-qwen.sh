#!/bin/bash
# Forward qwen-9b-llm service from Windows worker (via Colima) to Mac localhost:8080

# Get current Colima SSH port
COLIMA_PORT=$(colima ssh-config 2>/dev/null | grep "Port" | awk '{print $2}')
if [ -z "$COLIMA_PORT" ]; then
    echo "Error: Could not get Colima SSH port. Is Colima running?"
    exit 1
fi

echo "Setting up port forward: Mac:8080 -> Colima -> Windows worker:30081"
echo "Colima SSH port: $COLIMA_PORT"

# Kill any existing forward on port 8080
lsof -ti:8080 2>/dev/null | xargs kill -9 2>/dev/null

# Set up SSH tunnel through Colima to Windows worker
ssh -p "$COLIMA_PORT" \
    -L 8080:100.75.183.62:30081 \
    -i ~/.colima/_lima/_config/user \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    user@127.0.0.1 \
    -N -f

if [ $? -eq 0 ]; then
    echo "Port forward active: http://localhost:8080"
    echo "Test: curl http://localhost:8080/v1/models"
else
    echo "Error: Failed to establish port forward"
    exit 1
fi
