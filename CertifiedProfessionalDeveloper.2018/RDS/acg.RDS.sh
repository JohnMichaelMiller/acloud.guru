#!/bin/bash 

### AWS CLI code for the RDS lab from the acloud.guru AWS
### Certified Develper Associate course 

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

region='us-east-1'
dbInstanceId='acloudguru-db-instance'

# get external ip and cidr
myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/28"

dbPort=3306

rdsSecurityGroupName='acg-rds-security-group'

# create the security group
rdsSecurityGroupId=$(aws ec2 create-security-group \
  --description "This SG allows mySQL traffic on port 3306 from the external ip" \
  --group-name $rdsSecurityGroupName | jq -r .GroupId)

# open port for mySQL
aws ec2 authorize-security-group-ingress \
  --group-id $rdsSecurityGroupId \
  --protocol tcp \
  --port 3306 \
  --cidr $myCidr
aws ec2 describe-security-groups  --group-ids $rdsSecurityGroupId

# Launch DB Instance
dbInstance=$(aws rds create-db-instance \
  --db-name acloudguru_db \
  --db-instance-identifier $dbInstanceId \
  --allocated-storage 20 \
  --db-instance-class db.t2.micro \
  --engine mysql \
  --master-username acloudguru \
  --master-user-password acloudguru \
  --license-model general-public-license \
  --engine-version 5.7 \
  --db-parameter-group-name default.mysql5.7 \
  --option-group-name default:mysql-5-7 \
  --vpc-security-group-ids $rdsSecurityGroupId \
  --tags Key=org,Value=acg \
  --copy-tags-to-snapshot
)

# wait for rds instance
aws rds wait db-instance-available \
  --db-instance-identifier $dbInstanceId 

dbEndpoint=$(aws rds describe-db-instances | jq -r '.DBInstances[].Endpoint.Address')
dbPort=$(aws rds describe-db-instances | jq -r '.DBInstances[].Endpoint.Port')
echo $dbEndpoint $dbPort

# launch new web instance with bootstrap script
# Create a key pair
mkdir -p ~/.ssh
keyName="ec2-alb-$region"
echo $keyName
#
# WIP to avoid error when key exists
#if [$(aws ec2 describe-key-pairs --filter  'Name=key-name,Values=$keyName' | jq '.KeyPairs | length==0')]
  aws ec2 create-key-pair --key-name $keyName | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem
#fi
#
chmod 400 ~/.ssh/$keyName.pem
ls ~/.ssh/$keyName.pem -l

# create the security group
ec2SecurityGroupId=$(aws ec2 create-security-group \
  --description "This SG allows traffic from the current external ip on port 80 and port 22 " \
  --group-name "WebDMZ" | jq -r .GroupId)

# open ports for ssh and http
aws ec2 authorize-security-group-ingress \
  --group-id $ec2SecurityGroupId \
  --protocol tcp \
  --port 22 \
  --cidr $myCidr
aws ec2 authorize-security-group-ingress \
  --group-id $ec2SecurityGroupId \
  --protocol tcp \
  --port 80 \
  --cidr $myCidr
aws ec2 describe-security-groups  --group-ids $ec2SecurityGroupId

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images \
  --filters "Name=description,Values=Amazon Linux 2 AMI*" \
    "Name=architecture,Values=x86_64" \
    "Name=block-device-mapping.volume-type,Values=gp2" \
    | jq -r '.Images | .[0] | .ImageId')
echo $ami

instanceType="t2.micro"

php="sudo chmod -R 777 /var/www
sudo cat > /var/www/html/connect.php <<EOF
<?php
\\\$username = \"acloudguru\";
\\\$password = \"acloudguru\";
\\\$hostname = \"$dbEndpoint\";
\\\$dbname = \"acloudguru_db\";
echo \"username(\\\$username), password(\\\$password), host(\\\$hostname), dbname(\\\$dbname)<br>\";
//connection to the database
\\\$dbhandle = mysql_connect(\\\$hostname, \\\$username, \\\$password) or die(\"Unable to connect to MySQL\");
echo \"Connected to MySQL using username - \\\$username, password - \\\$password, host - \\\$hostname<br>\";
\\\$selected = mysql_select_db(\\\$dbname, \\\$dbhandle) or die(\"Unabled to connect to MySQL db - check the database name and try again.\");
?>
EOF"

# Define user data
userData=$( cat <<EOF
#!/bin/bash  
echo "start userdata"
yum install httpd php php-mysql -y  
#yum update -y  
chkconfig httpd on  
service httpd start  
cd /var/www/html  
echo "<?php phpinfo();?>" > index.php
#wget https://s3.eu-west-2.amazonaws.com/acloudguru-example/connect.php
$php
echo "end userdata"
EOF
) 

echo "$userData"

# Launch 1 default linux l2 instance in the default vpc
instanceId=$(aws ec2 run-instances \
  --image-id $ami \
  --count 1 \
  --key-name $keyName \
  --security-group-ids $ec2SecurityGroupId \
  --associate-public-ip-address \
  --instance-type $instanceType \
  --user-data "$userData" \
  | jq -r '.Instances | .[0] | .InstanceId')
# Assertion

# Get the instance states
aws ec2 wait instance-running \
  --instance-ids $instanceId
aws ec2 describe-instances \
  --instance-ids $instanceId \
  | jq -r '.Reservations | .[] | .Instances | .[] | .InstanceId,.State'

# Get endpoint
publicDns=$(aws ec2 describe-instances \
  --instance-ids $instanceId \
  | jq -r '.Reservations | .[] | .Instances | .[] | .PublicDnsName')

# curl web serve instance
curl $publicDns | less

# Should not be able to connect
curl $publicDns/connect.php

# ssh to web instance
#ssh -i "~/.ssh/$keyName.pem" "ec2-user@$publicDns" 


# white list port 3306 traffic from the web dmz security group in the rds security group
aws ec2 authorize-security-group-ingress \
  --group-id $rdsSecurityGroupId \
  --protocol tcp \
  --port 3306 \
  --source-group $ec2SecurityGroupId

# show connection succeeds
curl $publicDns/connect.php


# Teardown
aws rds delete-db-instance \
  --db-instance-identifier $dbInstanceId \
  --skip-final-snapshot
aws rds wait db-instance-deleted \
  --db-instance-identifier $dbInstanceId

# Terminate the instances
aws ec2 terminate-instances \
  --instance-ids $instanceId \
  | jq -r '.TerminatingInstances | .[] | .InstanceId, .PreviousState, .CurrentState'
aws ec2 wait instance-terminated \
  --instance-ids $instanceId

# Delete key pair
aws ec2 delete-key-pair \
  --key-name $keyName
rm ~/.ssh/$keyName.pem -f

# Delete the security group
aws ec2 delete-security-group \
  --group-id $rdsSecurityGroupId

# Delete the security group
aws ec2 delete-security-group \
  --group-id $ec2SecurityGroupId

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
