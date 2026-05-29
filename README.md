# AWS Load Balancer & Auto Scaling Group — Hands-On Project

A practical walkthrough and automation scripts for setting up an **Application Load Balancer (ALB)** with two EC2 web servers, and a separate setup for an **Auto Scaling Group (ASG)** integrated with an ALB — all on AWS using Amazon Linux 2.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Part 1 — Application Load Balancer (Manual)](#part-1--application-load-balancer-manual)
5. [Part 2 — Auto Scaling Group + ALB (Manual)](#part-2--auto-scaling-group--alb-manual)
6. [Automated Scripts](#automated-scripts)
7. [Cleanup](#cleanup)
8. [Key Concepts](#key-concepts)

---

## Architecture Overview

```
                          Internet
                              │
                    ┌─────────▼─────────┐
                    │  Application Load  │
                    │   Balancer (ALB)   │
                    │  (internet-facing) │
                    └─────┬───────┬─────┘
                          │       │  Round-robin HTTP
               ┌──────────▼─┐   ┌▼──────────┐
               │  EC2 Web   │   │  EC2 Web  │
               │ Server #1  │   │ Server #2 │
               │  (httpd)   │   │  (httpd)  │
               └────────────┘   └───────────┘
```

In the ASG variant the EC2 instances are managed automatically:

```
                          Internet
                              │
                    ┌─────────▼─────────┐
                    │  Application Load  │
                    │   Balancer (ALB)   │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Target Group    │
                    │  (health-checked) │
                    └─────────┬─────────┘
                              │
                 ┌────────────▼────────────┐
                 │   Auto Scaling Group    │
                 │  min=1 / desired=2 / max=3 │
                 │  (Launch Template)      │
                 └─────────────────────────┘
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| AWS Account | Free tier eligible for t3.micro |
| AWS CLI v2 | `aws configure` with an IAM user that has EC2 + ELB + AutoScaling permissions |
| EC2 Key Pair | Create one in the EC2 console; note its name |
| Security Group | Allow inbound TCP **22** (SSH), **80** (HTTP), **443** (HTTPS) |
| Two public subnets | In different Availability Zones within the same VPC |

---

## Project Structure

```
ASG-LB-Project/
├── README.md
├── LICENSE
└── scripts/
    ├── user-data.sh       # EC2 bootstrap script (Apache install + hostname page)
    ├── setup-alb.sh       # Creates 2 EC2 instances + Target Group + ALB (CLI)
    ├── setup-asg.sh       # Creates Launch Template + ASG + ALB (CLI)
    ├── cleanup-alb.sh     # Tears down all resources created by setup-alb.sh
    └── cleanup-asg.sh     # Tears down all resources created by setup-asg.sh
```

---

## Part 1 — Application Load Balancer (Manual)

Follow these steps in the AWS Console to understand what the automation scripts do behind the scenes.

### Step 1 — Launch two EC2 instances

1. Go to **EC2 → Instances → Launch instances**.
2. Choose **Amazon Linux 2**, instance type **t3.micro**.
3. Select your Key Pair and Security Group (SSH + HTTP + HTTPS).
4. Expand **Advanced → User data** and paste the script below:

```bash
#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
cd /var/www/html
echo "<h1>$(hostname)</h1>" > index.html
```

5. Launch **two** instances this way (repeat or set count to 2).
6. Once running, visit each public IP in a browser to confirm Apache responds:
   - `http://<instance-1-public-ip>/`
   - `http://<instance-2-public-ip>/`

### Step 2 — Create a Target Group

1. Go to **EC2 → Target Groups → Create target group**.
2. Target type: **Instances**.
3. Protocol: **HTTP**, Port: **80**.
4. Health check path: `/index.html`.
5. Click **Next**, select both instances, click **Include as pending below**, then **Create target group**.

### Step 3 — Create the Load Balancer

1. Go to **EC2 → Load Balancers → Create load balancer**.
2. Select **Application Load Balancer**.
3. Scheme: **Internet-facing**, IP address type: **IPv4**.
4. Select **all Availability Zones** (map all subnets).
5. Security Group: ensure **HTTP (80)** and **HTTPS (443)** are allowed.
6. Listener: **HTTP:80 → forward to** your Target Group.
7. Create — note the **DNS name** (e.g., `http://myloadbalancer-xxxx.us-east-1.elb.amazonaws.com`).

Refresh the URL multiple times — each refresh should show a different hostname, confirming round-robin distribution.

### Step 4 — Cleanup

1. Deregister instances from the Target Group.
2. Delete the Target Group.
3. Delete the Load Balancer.
4. Terminate both EC2 instances.

---

## Part 2 — Auto Scaling Group + ALB (Manual)

### Step 1 — Create a Launch Template

1. Go to **EC2 → Launch Templates → Create launch template**.
2. AMI: **Amazon Linux 2**, Instance type: **t3.micro**.
3. Key Pair and Security Group (SSH + HTTP + HTTPS).
4. **Advanced → User data** — paste the same script from Part 1.

### Step 2 — Create an Auto Scaling Group

1. Go to **EC2 → Auto Scaling Groups → Create Auto Scaling group**.
2. Name: `myASG`, select the Launch Template created above.
3. Select your **VPC** and **all Availability Zone subnets**.
4. **Attach a new load balancer**:
   - Type: **Application Load Balancer**, scheme: **Internet-facing**.
   - Target Group: create new, health check path `/index.html`.
5. Set capacity:
   - Minimum: **1**
   - Desired: **2**
   - Maximum: **3**
6. Create the ASG.

### Step 3 — Test self-healing

1. Manually **terminate one instance** from the EC2 console.
2. Wait ~60 seconds — the ASG detects the health check failure and automatically launches a replacement instance.

### Step 4 — Cleanup

1. Delete the **Auto Scaling Group** (this terminates managed instances).
2. Delete the **Load Balancer**.
3. Delete the **Target Group**.
4. Delete the **Launch Template**.

---

## Automated Scripts

All manual steps above are fully automated via AWS CLI scripts in the `scripts/` directory.

### Quick start

```bash
# 1. Make scripts executable
chmod +x scripts/*.sh

# 2. Edit configuration variables at the top of the script you want to run
#    (REGION, KEY_NAME, SG_ID, SUBNET_1, SUBNET_2)
nano scripts/setup-alb.sh   # or setup-asg.sh

# 3a. Deploy ALB + 2 static instances
./scripts/setup-alb.sh

# 3b. — OR — Deploy ASG + ALB
./scripts/setup-asg.sh
```

### Script reference

| Script | Purpose |
|---|---|
| `scripts/user-data.sh` | EC2 bootstrap — installs Apache and creates the hostname page |
| `scripts/setup-alb.sh` | Launches 2 instances, Target Group, ALB, and HTTP listener |
| `scripts/setup-asg.sh` | Creates Launch Template, Target Group, ALB, and ASG |
| `scripts/cleanup-alb.sh` | Removes all resources created by `setup-alb.sh` |
| `scripts/cleanup-asg.sh` | Removes all resources created by `setup-asg.sh` |

> **Tip:** Each setup script saves resource ARNs/IDs to a `.env` file (e.g., `.alb-resources.env`) so the corresponding cleanup script can find and delete exactly what was created.

---

## Cleanup

```bash
# Remove ALB + EC2 instances (Part 1)
./scripts/cleanup-alb.sh

# Remove ASG + ALB + Launch Template (Part 2)
./scripts/cleanup-asg.sh
```

---

## Key Concepts

| Concept | Description |
|---|---|
| **Application Load Balancer (ALB)** | Layer-7 load balancer that distributes HTTP/HTTPS traffic across registered targets. Internet-facing ALBs have a public DNS name. |
| **Target Group** | A logical group of EC2 instances (or IPs/Lambdas) that receive traffic from the ALB. Each target is health-checked on a configurable HTTP path. |
| **Health Check** | Periodic HTTP GET to `/index.html`; an instance is only sent traffic when it returns HTTP 200. |
| **Auto Scaling Group (ASG)** | Automatically maintains the desired number of EC2 instances. Replaces unhealthy instances and scales out/in based on demand. |
| **Launch Template** | Reusable instance configuration (AMI, type, key pair, SG, user data) used by the ASG to launch new instances. |
| **User Data** | A shell script executed once at first boot of an EC2 instance — used here to install and start Apache. |
| **Desired / Min / Max capacity** | ASG operates between min (1) and max (3) instances, targeting desired (2) under normal conditions. |
