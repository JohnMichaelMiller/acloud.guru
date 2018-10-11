#!/bin/bash 

### Implement the acloud.guru RDS Lab steps as bash and CF.

# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

# turn off history expansion
set +H

# Bucket names must be globally unique, change accordingly
bucketName='acloudguru1234-jmm'

cleanup=${1:-0} # pass a 1 to run cleanup code only

if [[$cleanup -eq 0]]

  # Create Stack
stackName="acg-rds"

region="us-east-1"
aws configure set default.region $region

### Implement the acloud.guru EC2 101 Lab steps as CF and bash.

# Get the current external IP address and create a CIDR
myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/32"

# Create a key pair
keyName="acg-rds-$region"
mkdir -p ~/.ssh
aws ec2 create-key-pair \
  --key-name $keyName \
  | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem
chmod 400 ~/.ssh/$keyName.pem

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images \
  --filters "Name=description,Values=Amazon Linux 2 AMI*" \
    "Name=architecture,Values=x86_64" \
    "Name=block-device-mapping.volume-type,Values=gp2" \
    | jq -r '.Images | .[0] | .ImageId')
echo $ami

# Get VPC and Subnet Ids
vpcId=$(aws ec2 describe-vpcs \
  --filter "Name=isDefault,Values=true" \
  | jq -r ".Vpcs | .[] | .VpcId")
echo $vpcId

subnet=$(aws ec2 describe-subnets \
  --filter "Name=vpc-id,Values=$vpcId" \
  | jq -r ".Subnets | .[0] | .SubnetId")
az=$(aws ec2 describe-subnets \
  --filter "Name=vpc-id,Values=$vpcId" \
  | jq -r ".Subnets | .[0] | .AvailabilityZone")

echo $keyName, $myIp, $myCidr, $vpcId, $subnet

# Instance properties
instanceType="t2.micro"
dbInstanceType="db.t2.micro"
instanceName="acg-rds-instance"

# The CloudFormation template to create the security group and the instance
# Include acg.rds.cf.yaml
cat > temp.cf.yaml <<EOF
---
AWSTemplateFormatVersion: 2010-09-09
Description: acloud.guru RDS Lab
Outputs:
  instanceId:
    Description: Instance Identifier
    Export:
      Name: 'rds:InstanceId'
    Value: !Ref ec2Instance
  instancePublicDNS:
    Description: Instance Public DNS
    Export:
      Name: 'rds:PublicDNS'
    Value: !GetAtt ec2Instance.PublicDnsName
  instancePublicIp:
    Description: Instance Public Ip
    Export:
      Name: 'rds:PublicIp'
    Value: !GetAtt ec2Instance.PublicIp
  securityGroupId:
    Description: Security Group Id
    Export:
      Name: 'rds:SecurityGroupId'
    Value: !GetAtt ec2SecurityGroup.GroupId
Parameters:      # Default values for template parameters are useful when testing templates in the AWS Web Console
  externalCidr:
    Type: String
    Default: 68.5.90.175/32 # default value is intentially incorrect
  imageId:
    Description: choose a valid ami for the instance type being deployed in your region
    Type: String
    Default: ami-04681a1dbd79675a5 # may not be correct 
  instanceName:
    ConstraintDescription: must be a unique instance name.
    Description: Name of the EC2 instance
    Type: String
    Default: acg-rds-instance
  instanceType:
    Type: String
    Default: t2.micro
  dbInstanceType:
    Type: String
    Default: db.t2.micro
  keyName:
    Description: >-
      Name of an existing EC2 KeyPair in this region to enable SSH access to
      Linux instance and/or decrypt Windows password
    Type: 'AWS::EC2::KeyPair::KeyName'
    Default: acg-rds-us-east-1
  vpcId:
    Description: The id of the VPC to deploy into
    Type: String
    Default: vpc-f3d7158a # intentionaly incorrect
  subNet:
    Description: An existing subnet in the VPC
    Type: String
    Default: subnet-c4732bf8 # intentionaly incorrect
  aZ:
    Description: The availability zone hosting the instance
    Type: String
    Default: us-east-1a # may not be correct
Resources:
  ec2Instance:
    Type: 'AWS::EC2::Instance'
    Metadata:
      'AWS::CloudFormation::Init':
        config:
          packages:
            yum:
              httpd: []
              php: []
              php-mysql: []
          files:
            /var/www/html/index.php:
              content: >-
                <?php phpinfo();?>
              group: apache
              mode: '000644'
              owner: apache
            /var/www/html/connect.php:
              content: !Join
              - ''
              - - |
                <?php
                \$username = "acloudguru";
                \$password = "acloudguru";
                \$hostname = "
                - ${Fn::GetAtt: MyDB, Endpoint.Address}
                - |
                ";
                \$dbname = "acloudguru_db";
                echo "username(\$username), password(\$password), host(\$hostname), dbname(\$dbname)<br>";
                //connection to the database
                \$dbhandle = mysql_connect(\$hostname, \$username, \$password) or die("Unable to connect to MySQL");
                echo "Connected to MySQL using username - \$username, password - \$password, host - \$hostname<br>";
                $selected = mysql_select_db(\$dbname, \$dbhandle) or die("Unabled to connect to MySQL db - check the database name and try again.");
                ?>
              group: apache
              mode: '000644'
              owner: apache
          services:
            sysvinit:
              httpd:
                enabled: 'true'
                ensureRunning: 'true'
      Comment: Install web server
    Properties:
      AvailabilityZone: !Ref aZ
      ImageId: !Ref imageId
      InstanceType: !Ref instanceType
      KeyName: !Ref keyName
      SecurityGroupIds:
        - !Ref ec2SecurityGroup
      Tags:
        - Key: Name
          Value: !Join 
            - ''
            - - !Ref instanceName
        - Key: Lab
          Value: acloud.guru.rds
      UserData:
        'Fn::Base64': !Sub >
          #!/bin/bash -xe

          echo start userdata

          /opt/aws/bin/cfn-init -v --stack \${AWS::StackName} --resource
          ec2Instance --region \${AWS::Region}

          yum update -y

          echo end userdata
  ec2SecurityGroup:
    Properties:
      GroupDescription: >-
        This SG allows traffic from the current external ip on port 80 and port
        22
      GroupName: ec2SecurityGroup
      SecurityGroupIngress:
        - CidrIp: !Ref externalCidr
          IpProtocol: tcp
          FromPort: 22
          ToPort: 22
        - CidrIp: 0.0.0.0/0
          IpProtocol: tcp
          FromPort: 80
          ToPort: 80
      VpcId: !Ref vpcId
      Tags:
        - Key: Name
          Value: rdsWebDMZ
        - Key: Lab
          Value: acloud.guru.rds
    Type: 'AWS::EC2::SecurityGroup'
    Metadata:
      'AWS::CloudFormation::Designer':
        id: be134cc2-eab8-4548-90bc-0d896775aa52
EOF

aws s3 cp temp.cf.yaml "s3://$bucketName"
url=$(aws s3 presign "s3://$bucketName/temp.cf.yaml")

# Validate that the template is well formed
aws cloudformation validate-template \
  --template-url $url

# Build the template parameter list
templateParameters="ParameterKey=externalCidr,ParameterValue=$myCidr "\
"ParameterKey=imageId,ParameterValue=$ami "\
"ParameterKey=instanceType,ParameterValue=$instanceType "\
"ParameterKey=dbInstanceType,ParameterValue=$dbInstanceType "\
"ParameterKey=instanceName,ParameterValue=$instanceName "\
"ParameterKey=keyName,ParameterValue=$keyName "\
"ParameterKey=aZ,ParameterValue=$az"
"ParameterKey=vpcId,ParameterValue=$vpcId"
"ParameterKey=subnet,ParameterValue=$subnet"

echo "$templateParameters"

# Create the stack
aws cloudformation create-stack \
  --stack-name $stackName \
  --template-url $url \
  --parameters $templateParameters \
  --disable-rollback \
  --capabilities CAPABILITY_IAM \
  --tags Key=group,Value=acloud.guru

aws cloudformation wait stack-create-complete \
  --stack-name $stackName

# aws cloudformation update-stack --stack-name $stackName --template-url $url --parameters $templateParameters --capabilities CAPABILITY_IAM --tags Key=group,Value=acloud.guru

# Monitor the stack creation status
aws cloudformation describe-stacks \
  | jq -r ".Stacks[].StackStatus"

# Get the stack output values
outputs=$(aws cloudformation describe-stacks \
  | jq -c '.Stacks[].Outputs')
securityGroupId=$(echo $outputs \
  | jq -r '.[] | select(.OutputKey | contains("securityGroupId")) | .OutputValue')
instancePublicDns=$(echo $outputs \
  | jq -r '.[] | select(.OutputKey | contains("instancePublicDNS")) | .OutputValue')
instancePublicIp=$(echo $outputs \
  | jq -r '.[] | select(.OutputKey | contains("instancePublicIp")) | .OutputValue')
echo $securityGroupId $instancePublicDns $instancePublicIp


curl $instancePublicDns | tail
curl $instancePublicDns/connect.php

ssh -i "~/.ssh/$keyName.pem" "ec2-user@$instancePublicDns"

else

  ## Cleanup

  rm temp.cf.yaml

  # Delete the stack
  aws cloudformation delete-stack --stack-name $stackName
  aws cloudformation wait stack-delete-complete \
    --stack-name $stackName

  # Delete key pair
  aws ec2 delete-key-pair --key-name $keyName
  rm ~/.ssh/$keyName.pem -f
fi 
