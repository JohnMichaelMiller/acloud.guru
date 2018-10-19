#!/bin/bash 

### AWS CLI code for the EC2 101 lab from the acloud.guru AWS
### Certified Develper Associate course

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

## Create a security group

# get external ip and cidr
myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/28"

# create the security group
securityGroupId=$(aws ec2 create-security-group --description "This SG allows traffic from the current external ip on port 80 and port 22 " --group-name "WebDMZ" | jq -r .GroupId)

# open ports for ssh and http
aws ec2 authorize-security-group-ingress \
  --group-id $securityGroupId \
  --protocol tcp \
  --port 22 \
  --cidr $myCidr
aws ec2 authorize-security-group-ingress \
  --group-id $securityGroupId \
  --protocol tcp \
  --port 80 \
  --cidr $myCidr

# Show that the sg was created
aws ec2 describe-security-groups \
--group-ids $securityGroupId


## EC2 Create, describe and terminate default Linux instance in the default region

# Create a key pair
mkdir -p ~/.ssh
keyName='EC2.101'
#!: Make idempotent
aws ec2 create-key-pair --key-name $keyName \
  | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem
chmod 400 ~/.ssh/$keyName.pem

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images \
  --filters "Name=description,Values=Amazon Linux 2 AMI*" \
    "Name=architecture,Values=x86_64" \
    "Name=block-device-mapping.volume-type,Values=gp2" \
    | jq -r '.Images | .[0] | .ImageId')
echo $ami

instanceType="t2.micro"

# Launch 1 default linux l2 instance in the default vpc
instanceId=$(aws ec2 run-instances \
  --image-id $ami \
  --count 1 \
  --key-name $keyName \
  --security-group-ids $securityGroupId \
  --associate-public-ip-address \
  --instance-type $instanceType \
  | jq -r '.Instances | .[0] | .InstanceId')
# Assertion
echo $instanceId

# Get the instance states
#!: Wait before proceeding
aws ec2 wait instance-running \
  --instance-ids $instanceId
aws ec2 describe-instances \
  --instance-ids $instanceId \
  | jq -r '.Reservations | .[] | .Instances | .[] | .InstanceId,.State'

# logon to instance
publicDNS=$(aws ec2 describe-instances \
  --instance-ids $instanceId \
  | jq -r '.Reservations | .[] | .Instances | .[] | .NetworkInterfaces | .[] | .Association.PublicDnsName')

# Assertion
echo $publicDNS

#connect to instance
ssh -i "~/.ssh/$keyName.pem" "ec2-user@$publicDNS"

# Server Prep
sudo su
yum update -y
yum install httpd -y
service httpd start
chkconfig httpd on
  
service httpd status

cd /var/www/html
# Assert that the index.html file does not exist
ls
# Create the web page.
echo "<html><body><h1>Hello Cloud Gurus</h1></body></html>" > index.html
# Assert that index.html file does exist
ls

exit # root
exit # shell

# Assert that the web page is returned without error
curl $publicDNS


## Clean-up 

# Terminate the instances
aws ec2 terminate-instances \
  --instance-ids $instanceId \
  | jq -r '.TerminatingInstances | .[] | .InstanceId, .PreviousState, .CurrentState'

# Delete key pair
aws ec2 delete-key-pair \
  --key-name $keyName
rm ~/.ssh/$keyName.pem -f

# Delete the security group
aws ec2 delete-security-group \
  --group-id $securityGroupId 

# This code is not idempotent. It assumes that none of these
# resources exists in the default vpc. It does try and clean up
# after itself. It is also not intended to be run as a command.
# The intent is to run each section or snippet in conjunction
# with the appropriate section of the lab. However, it should
# run attended but this hasn't been tested. This script assumes
# that none of the requisite AWS resources exist. To use existing
# resources assign the AWS resources identifiers to the appropriate
# vars and comment out the related code.

# MIT License

# Copyright (c) 2018 John Michael Miller

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
