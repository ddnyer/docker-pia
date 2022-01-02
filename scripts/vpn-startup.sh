#! /bin/bash

echo "Setup PIA VPN"

# Create a TUN device
mkdir -p /dev/net
mknod /dev/net/tun c 10 200
chmod 0666 /dev/net/tun

# Create docker user
usermod -u $PUID docker_user
groupmod -g $PGID docker_group
chown -R docker_user:docker_group /config

# Start the PIA service

/opt/piavpn/bin/pia-daemon &
sleep 2

# Set debug logging

piactl set debuglogging $PIA_DEBUG_LOGGING

if [ ! $? -eq 0 ]; then
    echo "Failed to set PIA log level"
    exit 5;
fi

# Log in to PIA

echo -e "$PIA_USERNAME\n$PIA_PASSWORD\n" > /pia_credentials
cat /pia_credentials
piactl login /pia_credentials

if [ ! $? -eq 0 ]; then
    echo "Failed to log in to PIA"
    exit 5;
fi

# Enable background service operation

piactl background enable

if [ ! $? -eq 0 ]; then
    echo "Failed to enable PIA background"
    exit 5;
fi

# Add dedicated IP

echo "Set dedicate IP"
if [ ! -z $PIA_DEDICATED_IP_TOKEN ]; then

    echo "Add dedicated IP region"    
    echo -e "$PIA_DEDICATED_IP_TOKEN" > /pia_dedicated_ip_token 
    piactl dedicatedip add /pia_dedicated_ip_token

    if [ ! $? -eq 0 ]; then
        echo "Failed to add dedicated IP"
        exit 5;
    fi

fi

piactl set protocol $PIA_PROTOCOL

if [ ! $? -eq 0 ]; then
    echo "Failed to set PIA protocol"
    exit 5;
fi

piactl set requestportforward $PIA_PORT_FORWARD

if [ ! $? -eq 0 ]; then
    echo "Failed to set request port forwarding"
    exit 5;
fi

piactl set region $PIA_REGION

if [ ! $? -eq 0 ]; then
    echo "Failed to set PIA region"
    exit 5;
fi

# Connect to the VPN

echo "Connect to $(piactl get region)"

piactl connect

if [ ! $? -eq 0 ]; then
    echo "Failed to connect to PIA VPN"
    exit 5;
fi

# Wait for the connection to come up

i="0"
/opt/scripts/vpn-health-check.sh
while [[ ! $? -eq 0 ]]; do
    sleep 2
    echo "Waiting for the VPN to connect... $i"
    i=$[$i+1]
    if [[ $i -eq "10" ]]; then
        exit 5
    fi
    /opt/scripts/vpn-health-check.sh
done

export VPN_PORT=$(piactl get portforward)
echo "Port forward is $VPN_PORT"

# Run the setup script for the environment
/opt/scripts/app-setup.sh

# Run the user app in the docker container
su -w VPN_PORT -g docker_group - docker_user -c "/opt/scripts/app-startup.sh"

