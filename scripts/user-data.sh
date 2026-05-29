#!/bin/bash
# =============================================================================
# File        : user-data.sh
# Description : EC2 Launch Template / User Data script.
#               Runs automatically on first boot of an Amazon Linux 2 instance.
#               Installs Apache HTTP Server, starts the service, and creates a
#               simple index page that displays the instance hostname — useful
#               for verifying which EC2 instance a Load Balancer routes traffic
#               to during testing.
#
# Usage       : Paste the contents of this file into the "User data" field when
#               creating an EC2 Launch Template or when launching an instance
#               manually via the AWS Console or CLI.
#
# Tested on   : Amazon Linux 2 (ami-0c55b159cbfafe1f0)
# =============================================================================

# Update all installed packages to the latest version
yum update -y

# Install the Apache HTTP Server (httpd)
yum install httpd -y

# Start the Apache service immediately
systemctl start httpd

# Enable Apache to start automatically on every reboot
systemctl enable httpd

# Navigate to the web root directory
cd /var/www/html

# Create a simple HTML page showing the EC2 hostname.
# The $(hostname) command is evaluated at boot time, so each instance
# will display its own unique hostname — helpful when testing that the
# Load Balancer distributes traffic across multiple instances.
echo "<h1>Hello from $(hostname)</h1>" > index.html
