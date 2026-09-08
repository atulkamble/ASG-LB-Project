#!/bin/bash
dnf update -y
dnf install -y httpd
systemctl enable --now httpd
echo "<h1>Webserver: $(hostname)</h1>" > /var/www/html/index.html
