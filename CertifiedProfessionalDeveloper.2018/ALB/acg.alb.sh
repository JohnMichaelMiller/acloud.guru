#!/bin/bash 

### Implement the acloud.guru Load Balancer Lab steps as bash.
# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

region="us-east-1"
aws configure set default.region $region

# Create a key pair
mkdir -p ~/.ssh
keyName="ec2-alb-$region"
echo $keyName

# WIP to avoid error when key exists
#if [$(aws ec2 describe-key-pairs --filter  'Name=key-name,Values=$keyName' | jq '.KeyPairs | length==0')]
  aws ec2 create-key-pair \
    --key-name $keyName \
    | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem
#fi

chmod 400 ~/.ssh/$keyName.pem

# Create a security group 
securityGroupId=$(aws ec2 create-security-group \
  --description "This ALB SG allows traffic only on port 80 and port 22" \
  --group-name "ALBWebDMZ" \
  | jq -r .GroupId)
echo $securityGroupId

myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/32"
allCidr="0.0.0.0/0"

aws ec2 authorize-security-group-ingress \
  --group-id $securityGroupId \
  --protocol tcp \
  --port 22 \
  --cidr $myCidr
aws ec2 authorize-security-group-ingress \
  --group-id $securityGroupId \
  --protocol tcp \
  --port 80 \
  --cidr $allCidr
aws ec2 describe-security-groups 
  --group-ids $securityGroupId \
  | jq -r ".SecurityGroups[].GroupId"

# Get VPC and Subnet Ids
vpcId=$(aws ec2 describe-vpcs \
  --filter "Name=isDefault,Values=true" \
  | jq -r ".Vpcs | .[] | .VpcId")
echo $vpcId

subnet1=$(aws ec2 describe-subnets \
  --filter "Name=vpc-id,Values=$vpcId" \
  | jq -r ".Subnets | .[0] | .SubnetId")
subnet2=$(aws ec2 describe-subnets \
  --filter "Name=vpc-id,Values=$vpcId" \
  | jq -r ".Subnets | .[1] | .SubnetId")

echo $subnet1, $subnet2

echo $keyName, $securityGroupId, $myIp, $myCidr, $vpcId, $subnet1, $subnet2


# Create a couple of instances to load balance

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images \
  --filters "Name=description,Values=Amazon Linux 2 AMI*" \
    "Name=architecture,Values=x86_64" \
    "Name=block-device-mapping.volume-type,Values=gp2" \
    | jq -r '.Images | .[0] | .ImageId')
echo $ami

instanceType="t2.micro"

# Define user data
IFS='' read -r -d '' userData <<"EOF"
#!/bin/bash
echo "start userdata"
sudo su
yum update -y
yum install httpd -y
service httpd start
chkconfig httpd on

service httpd status

cd /var/www/html
ls
 echo "<html><body><h1>Hello Cloud Gurus</h1></body></html>" > index.html
ls
echo "end userdata"
EOF

echo "$userData"

# Placement
availabilityZones=$(aws ec2 describe-availability-zones)
availabilityZone=$(echo "$availabilityZones" \
  | jq -r ".AvailabilityZones[0].ZoneName")
echo $availabilityZone

placement="AvailabilityZone=$availabilityZone,Tenancy=default"
echo $placement

# Launch 2 default linux instances in the default vpc
instances=$(aws ec2 run-instances \
  --image-id $ami \
  --count 2 \
  --key-name $keyName \
  --security-group-ids $securityGroupId \
  --associate-public-ip-address \
  --instance-type $instanceType \
  --user-data "$userData" \
  --placement $placement \
  )

instanceId1=$(echo $instances \
  | jq -r '.Instances | .[0] | .InstanceId')
instanceId2=$(echo $instances \
  | jq -r '.Instances | .[1] | .InstanceId')

echo $instanceId1, $instanceId2

aws ec2 wait instance-running \
  --instance-ids $instanceId1 $instanceId2

aws ec2 describe-instances \
  --instance-ids $instanceId1 $instanceId2 \
  | jq -r ".Reservations[].Instances[].State"

publicDNS1=$(aws ec2 describe-instances \
  --instance-ids $instanceId1 $instanceId2 \
  | jq -r ".Reservations[].Instances[0].NetworkInterfaces[].Association.PublicDnsName")
publicDNS2=$(aws ec2 describe-instances \
  --instance-ids $instanceId1 $instanceId2 \
  | jq -r ".Reservations[].Instances[0].NetworkInterfaces[].Association.PublicDnsName")

echo $publicDNS1, $publicDNS2

curl $publicDNS1
curl $publicDNS2

loadBalancer=$(aws elbv2 create-load-balancer \
  --name my-application-load-balancer \
  --subnets $subnet1 $subnet2 \
  --security-groups $securityGroupId)

loadBalancerArn=$(echo "$loadBalancer" \
  | jq -r ".LoadBalancers[].LoadBalancerArn")
echo $loadBalancerArn
loadBalancerDns=$(echo "$loadBalancer" \
  | jq -r ".LoadBalancers[].DNSName")
echo $loadBalancerDns

targetGroupArn=$(aws elbv2 create-target-group \
  --name my-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id $vpcId \
  | jq -r ".TargetGroups[].TargetGroupArn")
echo $targetGroupArn

aws elbv2 register-targets \
  --target-group-arn $targetGroupArn \
  --targets Id=$instanceId1 Id=$instanceId2

listenerArn=$(aws elbv2 create-listener \
  --load-balancer-arn $loadBalancerArn \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$targetGroupArn 
  | jq -r ".Listeners[].ListenerArn")
echo "$listenerArn"

aws elbv2 describe-target-health \
  --target-group-arn $targetGroupArn

curl $loadBalancerDns


## Cleanup

# Delete load balancer
aws elbv2 delete-load-balancer \
  --load-balancer-arn $loadBalancerArn
aws elbv2 delete-target-group \
  --target-group-arn $targetGroupArn

# Terminate the instances
aws ec2 terminate-instances \
  --instance-ids $instanceId1 $instanceId2 \
  | jq -r '.TerminatingInstances | .[] | .InstanceId, .PreviousState, .CurrentState'

# Delete key pair
aws ec2 delete-key-pair \
  --key-name $keyName
rm ~/.ssh/$keyName.pem -f
ls ~/.ssh

# Delete the security group
aws ec2 delete-security-group \
  --group-id $securityGroupId 
