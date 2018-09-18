#!/bin/bash 

# turn off history expansion
set +H

### Implement the acloud.guru EC2 101 Lab steps as CF and bash.

# Get the current external IP address and create a CIDR
myIp=$(dig +short myip.opendns.com @resolver1.opendns.com)
myCidr="$myIp/32"

# Create a key pair
mkdir -p ~/.ssh
keyName='EC2.101'
aws ec2 create-key-pair --key-name $keyName | jq -r ".KeyMaterial" > ~/.ssh/$keyName.pem
chmod 400 ~/.ssh/$keyName.pem

# Get the default Linux AMI for the current region
ami=$(aws ec2 describe-images --filters "Name=description,Values=Amazon Linux 2 AMI*" "Name=architecture,Values=x86_64" "Name=block-device-mapping.volume-type,Values=gp2"| jq -r '.Images | .[0] | .ImageId')
echo $ami

# Instance properties
instanceType="t2.micro"
instanceName="acloud.guru.ec2.101"

# The CloudFormation template to create the security group and the instance
cfTemplate=$( cat <<EOF
--- 
AWSTemplateFormatVersion: "2010-09-09"
Description: "acloud.guru EC2 101 Lab"
Outputs: 
  instancePublicDNS: 
    Description: "Instance Public DNS"
    Export: 
      Name: "EC2:101:PublicDNS"
    Value: !GetAtt EC2101LabInstance.PublicDnsName
  instancePublicIp: 
    Description: "Instance Public Ip"
    Export: 
      Name: "EC2:101:PublicIp"
    Value: !GetAtt EC2101LabInstance.PublicIp
  securityGroupId: 
    Description: "Security Group Id"
    Export: 
      Name: "EC2:101:SecurityGroupId"
    Value: !GetAtt webDMZ.GroupId
Parameters: 
  externalCidr: 
    Type: String
  imageId: 
    Description: "choose a valid ami for the instance type being deployed in your region"
    Type: String
  instanceName: 
    ConstraintDescription: "must be a unique instance name."
    Description: "Name of the EC2 instance"
    Type: String
  instanceType: 
    Type: String
  keyName: 
    Description: "Name of an existing EC2 KeyPair in this region to enable SSH access to Linux instance and/or decrypt Windows password"
    Type: "AWS::EC2::KeyPair::KeyName"
  vpcId: 
    Type: String
Resources: 
  EC2101LabInstance: 
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
                <html><body><h1>Hello Cloud Gurus</h1></body></html>
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
      ImageId: !Ref imageId
      InstanceType: !Ref instanceType
      KeyName: !Ref keyName
      SecurityGroupIds: 
      - !Ref webDMZ
      Tags: 
        - 
          Key: Name
          Value: !Ref instanceName
      UserData: # Patch kick off the cfn-init and patch the server
        ? "Fn::Base64"
        : !Sub |
            #!/bin/bash -xe
            echo start userdata
            /opt/aws/bin/cfn-init -v --stack \${AWS::StackName} --resource EC2101LabInstance --region \${AWS::Region}
            yum update -y
            echo end userdata
  webDMZ: 
    Properties: 
      GroupDescription: "This SG allows traffic from the current external ip on port 80 and port 22"
      GroupName: WebDMZ
      SecurityGroupIngress: 
        - 
          CidrIp: !Ref externalCidr
          IpProtocol: tcp
          FromPort: 22
          ToPort: 22
        - 
          CidrIp: !Ref externalCidr
          IpProtocol: tcp
          FromPort: 80
          ToPort: 80
      VpcId: !Ref vpcId
    Type: "AWS::EC2::SecurityGroup"
EOF
) 

# Validate that the template is well formed
aws cloudformation validate-template --template-body "$cfTemplate"

# Build the template parameter list
templateParameters="ParameterKey=externalCidr,ParameterValue=$myCidr ParameterKey=vpcId,ParameterValue=$vpcId ParameterKey=instanceType,ParameterValue=$instanceType ParameterKey=instanceName,ParameterValue=$instanceName ParameterKey=keyName,ParameterValue=$keyName ParameterKey=imageId,ParameterValue=$ami"
echo "$templateParameters"

# Create the stack
aws cloudformation create-stack --stack-name acloud-guru-ec2-101 --template-body "$cfTemplate" --parameters $templateParameters --disable-rollback --capabilities CAPABILITY_IAM --tags Key=group,Value=acloud.guru

# Monitor the stack creation status
aws cloudformation describe-stacks | jq -r ".Stacks[].StackStatus"

# Get the stack output values
outputs=$(aws cloudformation describe-stacks | jq -c '.Stacks[].Outputs')
securityGroupId=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("securityGroupId")) | .OutputValue')
instancePublicDns=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instancePublicDNS")) | .OutputValue')
instancePublicIp=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("instancePublicIp")) | .OutputValue')
echo $securityGroupId $instancePublicDns $instancePublicIp


# Inspect the security group
aws ec2 describe-security-groups  --group-ids $securityGroupId

# Hit the web site
curl $instancePublicDns
curl $instancePublicIp

## Cleanup

# Delete the stack
aws cloudformation delete-stack --stack-name "acloud-guru-ec2-101"

# Delete key pair
aws ec2 delete-key-pair --key-name $keyName
rm ~/.ssh/$keyName.pem
