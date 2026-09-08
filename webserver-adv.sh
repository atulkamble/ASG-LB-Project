#!/bin/bash

dnf update -y
dnf install -y httpd
systemctl enable --now httpd

# Generate random colors
BG_COLOR=$(printf '#%06X' $((RANDOM * RANDOM % 16777216)))
TEXT_COLOR=$(printf '#%06X' $((RANDOM * RANDOM % 16777216)))

# Create web page
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Web Server</title>
    <style>
        body {
            background-color: $BG_COLOR;
            color: $TEXT_COLOR;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            font-family: Arial, sans-serif;
        }

        h1 {
            text-align: center;
            font-size: 50px;
        }
    </style>
</head>

<body>
    <h1>Webserver: $(hostname)</h1>
</body>
</html>
EOF
