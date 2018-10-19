#!/bin/bash 

### AWS CLI code to deploy the CloudFormation template for the
### Application Load Balancer lab from the acloud.guru AWS 
### Certified Develper Associate course

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

# Change to an existing bucket in the account
bucketName="acg.alb.cf"
stackName="acg-alb"

region="us-east-1"
aws configure set default.region $region

### Implement the acloud.guru EC2 101 Lab steps as CF and bash.

# Get the current external IP address and create a CIDR
myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/28"
allCidr="0.0.0.0/0"

# Create a key pair
mkdir -p ~/.ssh
keyName="acg-alb-$region"
echo $keyName
aws ec2 create-key-pair --key-name $keyName | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images --filters "Name=description,Values=Amazon Linux 2 AMI*" "Name=architecture,Values=x86_64" "Name=block-device-mapping.volume-type,Values=gp2"| jq -r '.Images | .[0] | .ImageId')
echo $ami

# Get VPC and Subnet Ids
vpcId=$(aws ec2 describe-vpcs --filter "Name=isDefault,Values=true" | jq -r ".Vpcs | .[] | .VpcId")
echo $vpcId

subnet1=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=$vpcId" | jq -r ".Subnets | .[0] | .SubnetId")
az1=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=$vpcId" | jq -r ".Subnets | .[0] | .AvailabilityZone")
subnet2=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=$vpcId" | jq -r ".Subnets | .[1] | .SubnetId")
az2=$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=$vpcId" | jq -r ".Subnets | .[1] | .AvailabilityZone")

echo $subnet1, $subnet2

echo $keyName, $securityGroupId, $myIp, $myCidr, $vpcId, $subnet1, $subnet2

# Instance properties
instanceType="t2.micro"
instanceName="acg.alb.instance"

# The CloudFormation template to create the security group and the instance
cfTemplate=$( cat <<EOF
--- 
AWSTemplateFormatVersion: "2010-09-09"
Description: "acloud.guru EC2 101 Lab"
Outputs: 
  instanceAId: 
    Description: "Instance Identifier"
    Export: 
      Name: "ALB:InstanceIdA"
    Value: !Ref ALBLabInstanceA
  instanceBId: 
    Description: "Instance Identifier"
    Export: 
      Name: "ALB:InstanceIdB"
    Value: !Ref ALBLabInstanceB
  instanceAPublicDNS: 
    Description: "Instance A Public DNS"
    Export: 
      Name: "ALB:PublicDNSA"
    Value: !GetAtt ALBLabInstanceA.PublicDnsName
  instanceAPublicIp: 
    Description: "Instance A Public Ip"
    Export: 
      Name: "ALB:PublicIpA"
    Value: !GetAtt ALBLabInstanceA.PublicIp
  instanceBPublicDNS: 
    Description: "Instance B Public DNS"
    Export: 
      Name: "ALB:PublicDNSB"
    Value: !GetAtt ALBLabInstanceB.PublicDnsName
  instanceBPublicIp: 
    Description: "Instance B Public Ip"
    Export: 
      Name: "ALB:PublicIpB"
    Value: !GetAtt ALBLabInstanceB.PublicIp
  securityGroupId: 
    Description: "Security Group Id"
    Export: 
      Name: "ALB:SecurityGroupId"
    Value: !GetAtt ALBWebDMZ.GroupId
  targetGroupArn:
    Description: "ALB Target Group ARN"
    Export: 
      Name: "ALB:TargetGroupArn"
    Value: !Ref MyTargetGroup
  httpListenerArn:
    Description: "HTTP Listener ARN"
    Export: 
      Name: "ALB:HTTPListenerArn"
    Value: !Ref MyHTTPListner
  applicationLoadBalancerArn:
    Description: "ALB ARN"
    Export: 
      Name: "ALB:Arn"
    Value: !Ref MyALB
  applicationLoadBalancerCanonicalHostedZoneID:
    Description: "The ID of the Amazon Route 53 hosted zone associated with the load balancer"
    Export: 
      Name: "ALB:CanonicalHostedZoneID"
    Value: !GetAtt MyALB.CanonicalHostedZoneID
  applicationLoadBalancerDnsName:
    Description: "The DNS name for the load balancer"
    Export: 
      Name: "ALB:DnsName"
    Value: !GetAtt MyALB.DNSName
  applicationLoadBalancerFullName:
    Description: "The full name of the load balancer"
    Export: 
      Name: "ALB:FullName"
    Value: !GetAtt MyALB.LoadBalancerFullName
  applicationLoadBalancerName:
    Description: "The name of the load balancer"
    Export: 
      Name: "ALB:Name"
    Value: !GetAtt MyALB.LoadBalancerName
Parameters: 
  externalCidr: 
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-8]))$
    Type: String
  imageId: 
    Description: "choose a valid ami for the instance type being deployed in your region"
    Type: AWS::EC2::Image::Id
  instanceName: 
    ConstraintDescription: "must be a unique instance name."
    Description: "Name of the EC2 instance"
    Type: String
  instanceType: 
    Type: String
    Default: t2.micro
  keyName: 
    Description: "Name of an existing EC2 KeyPair in this region to enable SSH access to Linux instance and/or decrypt Windows password"
    Type: "AWS::EC2::KeyPair::KeyName"
  vpcId: 
    Description: "The id of the VPC to deploy into"
    Type: AWS::EC2::VPC::Id
  firstSubnet:
    Description: "A subnet in the VPC"
    Type: String
  secondSubnet:
    Description: "Another subnet in the VPC"
    Type: String
  firstAZ:
    Description: "The AZ for the first subnet"
    Type: String
  secondAZ:
    Description: "The AZ for the second subnet"
    Type: String
Resources: 
  ALBLabInstanceA: 
    Type: "AWS::EC2::Instance"
    Metadata:
      AWS::CloudFormation::Init:
        config:
          packages:
            yum:
              httpd: []  # Install the httpd package
          files:  # Create the web page
            "/var/www/html/index.html":
              content: 
                <html><body><h1>Hello Cloud Gurus</h1><h2>from instance A</h2></body></html>
              group: apache
              mode: "000644"
              owner: apache
          services: # start the httpd service
            sysvinit:
              httpd:
                enabled: 'true'
                ensureRunning: 'true'
      Comment: "Install web server"
    Properties: 
      AvailabilityZone: !Ref firstAZ
      ImageId: !Ref imageId
      InstanceType: !Ref instanceType
      KeyName: !Ref keyName
      SecurityGroupIds: 
      - !Ref ALBWebDMZ
      Tags: 
      - 
        Key: Name
        Value: !Join
          - ''
          - - !Ref instanceName
            - '-a'
      - 
        Key: Lab
        Value: acloud.guru.alb
      UserData: # Patch kick off the cfn-init and patch the server
        ? "Fn::Base64"
        : !Sub |
            #!/bin/bash -xe
            echo start userdata
            /opt/aws/bin/cfn-init -v --stack \${AWS::StackName} --resource ALBLabInstanceA --region \${AWS::Region}
            yum update -y
            echo end userdata
  ALBWebDMZ: 
    Properties: 
      GroupDescription: "This SG allows traffic from the current external ip on port 80 and port 22"
      GroupName: ALBWebDMZ
      SecurityGroupIngress: 
      - 
        CidrIp: !Ref externalCidr
        IpProtocol: tcp
        FromPort: 22
        ToPort: 22
      - 
        CidrIp: 0.0.0.0/0
        IpProtocol: tcp
        FromPort: 80
        ToPort: 80
      VpcId: !Ref vpcId
      Tags:
      - 
        Key: Name
        Value: ALBWebDMZ
      - 
        Key: Lab
        Value: acloud.guru.alb
    Type: "AWS::EC2::SecurityGroup"
  ALBLabInstanceB: 
    Type: "AWS::EC2::Instance"
    Metadata:
      AWS::CloudFormation::Init:
        config:
          packages:
            yum:
              httpd: []  # Install the httpd package
          files:  # Create the web page
            "/var/www/html/index.html":
              content: 
                <html><body><h1>Hello Cloud Gurus</h1><h2>from instance B</h2></body></html>
              group: apache
              mode: "000644"
              owner: apache
          services: # start the httpd service
            sysvinit:
              httpd:
                enabled: 'true'
                ensureRunning: 'true'
      Comment: "Install web server"
    Properties: 
      AvailabilityZone: !Ref secondAZ
      ImageId: !Ref imageId
      InstanceType: !Ref instanceType
      KeyName: !Ref keyName
      SecurityGroupIds: 
      - !Ref ALBWebDMZ
      Tags: 
      - 
        Key: Name
        Value: !Join
          - ''
          - - !Ref instanceName
            - '-b'
      - 
        Key: Lab
        Value: acloud.guru.alb
      UserData: # Patch kick off the cfn-init and patch the server
        ? "Fn::Base64"
        : !Sub |
            #!/bin/bash -xe
            echo start userdata
            /opt/aws/bin/cfn-init -v --stack \${AWS::StackName} --resource ALBLabInstanceB --region \${AWS::Region}
            yum update -y
            echo end userdata
  MyALB:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Name: MyAppLoadBalancer
      SecurityGroups:
      - !Ref ALBWebDMZ
      Subnets:
      - !Ref firstSubnet
      - !Ref secondSubnet
      Tags:
      - 
        Key: Name
        Value: MyALB
      - 
        Key: Lab
        Value: acloud.guru.alb
  MyHTTPListner:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties: 
      LoadBalancerArn: !Ref MyALB
      Port: 80
      Protocol: HTTP
      DefaultActions:
      - 
        TargetGroupArn: !Ref MyTargetGroup
        Type: forward
  MyTargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      HealthCheckIntervalSeconds: 30
      HealthCheckPort: 80
      HealthCheckProtocol: HTTP
      HealthCheckTimeoutSeconds: 10
      HealthyThresholdCount: 4
      Matcher: 
        HttpCode: 200
      Name: MyTargets
      Port: 80
      Protocol: HTTP
      Tags:
      - 
        Key: Name
        Value: MyTargets
      - 
        Key: Lab
        Value: acloud.guru.alb
      Targets:
        - Id:
            !Ref ALBLabInstanceA
          Port: 80
        - Id:
            !Ref ALBLabInstanceB
          Port: 80
      UnhealthyThresholdCount: 3
      VpcId: !Ref vpcId
EOF
) 

echo "$cfTemplate" > temp.yaml

aws s3 cp temp.yaml "s3://$bucketName"
url=$(aws s3 presign "s3://$bucketName/test.cf.yaml")

# Validate that the template is well formed
aws cloudformation validate-template --template-url $url

# Build the template parameter list
templateParameters="ParameterKey=externalCidr,ParameterValue=$myCidr ParameterKey=vpcId,ParameterValue=$vpcId ParameterKey=instanceType,ParameterValue=$instanceType ParameterKey=instanceName,ParameterValue=$instanceName ParameterKey=keyName,ParameterValue=$keyName ParameterKey=imageId,ParameterValue=$ami ParameterKey=firstSubnet,ParameterValue=$subnet1 ParameterKey=secondSubnet,ParameterValue=$subnet2 ParameterKey=firstAZ,ParameterValue=$az1 ParameterKey=secondAZ,ParameterValue=$az2"

echo "$templateParameters"

# Create the stack
aws cloudformation create-stack --stack-name $stackName --template-url $url --parameters $templateParameters --disable-rollback --capabilities CAPABILITY_IAM --tags Key=group,Value=acloud.guru

aws cloudformation update-stack --stack-name $stackName --template-url $url --parameters $templateParameters --capabilities CAPABILITY_IAM --tags Key=group,Value=acloud.guru

# Monitor the stack creation status
aws cloudformation describe-stacks | jq -r ".Stacks[].StackStatus"

# Get the stack output values
outputs=$(aws cloudformation describe-stacks | jq -c '.Stacks[].Outputs')
securityGroupId=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("securityGroupId")) | .OutputValue')
instanceAPublicDns=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instanceAPublicDNS")) | .OutputValue')
instanceBPublicDns=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instanceBPublicDNS")) | .OutputValue')
instanceAPublicIp=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instanceAPublicIp")) | .OutputValue')
instanceBPublicIp=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instanceBPublicIp")) | .OutputValue')
ALBPublicDns=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("applicationLoadBalancerDnsName")) | .OutputValue')
echo $securityGroupId $instanceAPublicDns $instanceAPublicIp $instanceBPublicDns $instanceBPublicIp


# Inspect the security group
aws ec2 describe-security-groups  --group-ids $securityGroupId

# Hit the web servers
curl $instanceAPublicDns
curl $instanceAPublicIp
curl $instanceBPublicDns
curl $instanceBPublicIp

curl $ALBPublicDns

## Cleanup

rm temp.yaml

# Delete the stack
aws cloudformation delete-stack --stack-name $stackName

# Delete key pair
aws ec2 delete-key-pair --key-name $keyName
rm ~/.ssh/$keyName.pem

# Disclaimer: This script is not idempotent. It assumes that none
# of these resources exists in the default vpc. It does try and
# clean up after itself. It is also not intended to be run as a
# command. The intent is to run each section or snippet in
# conjunction with the appropriate section of the lab. However,
# it should run attended but this hasn't been tested. This script
# assumes that none of the requisite AWS resources exist. To use
# existing resources assign the AWS resources identifiers to the
# appropriate vars and comment out the related code.

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
