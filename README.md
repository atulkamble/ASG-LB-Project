Create Project 

LB - ASG 

1. Create Template >> Select AMI >> Instance type - t3/t2.micro , key.pem, SG
#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
cd /var/www/html
echo "<h1> hello from $(hostname)</h1>" > index.html

2. Create ASG >> Select Subnets/AZ 
Attach New - LB >> Internet Facing
min 1 >> desired 2 >> max 3

3. Target Group - health check path       /index.html 
4. security group of LB - 80 
5. check LB URL >> http://myasg-1-243681565.us-east-1.elb.amazonaws.com/

Load Balancer - Traffic Distribute

1. Launch 2 instances at the same time >> keep evrything defaults (t3.micro) - amazon linux
SG - ssh, http, https

2. Advanced >> user data

#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
cd /var/www/html
echo "<h1>$(hostname)</h1>" > index.html

3. check public ip of both instances simultaneously.
http://98.89.32.91/                          
http://34.227.227.17/

4. create target group
health check path \index.html
5. instances >> include as pending below
6. create target group
7. create load balancer - internet facing - 80
8. select target group
9. create load balancer >> select all availibility zones and map them.
10. check security group of load balancer as well - http, https
11. note down URL of load balancer
http://myloadbalancer-1193861558.us-east-1.elb.amazonaws.com
12. unregister instances from target group, delete target group, delete load balancer, terminate instances.



// AutoScaling Group

1. Create Template - webserver
Amazon Linux
SG - http, https, ssh

Advanced >> Custom Data >>

#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
cd /var/www/html
echo "<h1>$(hostname)</h1>" > index.html

Select VPS, SG, type- t3.micro

2. Create ASG
myASG

select template
Mapping

3. create ASG

desired capacity 2
minimum capacity 1  
maximum capacity 3

4. delete instances manually and let instances to be generated , wait for the same.

5. delete ASG*
