#!/bin/bash 

### Implement the acloud.guru CLI Lab steps as bash using CloudFormation.
# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

# turn off history expansion
set +H

# Change to an existing bucket in the account
bucketName="acg.alb.cf"

policyArn="arn:aws:iam::aws:policy/AdministratorAccess"
stackName="acg-cli"

region="us-east-1"
aws configure set default.region $region

### Implement the acloud.guru CLI Lab steps as CF and bash.

# The CloudFormation template to create the security group and the instance
cfTemplate=$( cat <<EOF
--- 
AWSTemplateFormatVersion: "2010-09-09"
Description: "acloud.guru CLI Lab"
Outputs: 
  userName: 
    Description: "The IAM User Name"
    Export: 
      Name: "CLI:UserName"
    Value: !Ref devUser
  userArn: 
    Description: "The IAM User ARN"
    Export: 
      Name: "CLI:UserArn"
    Value: !GetAtt devUser.Arn
  groupName: 
    Description: "The IAM Group Name"
    Export: 
      Name: "CLI:GroupName"
    Value: !Ref devGroup
  groupArn: 
    Description: "The IAM Group ARN"
    Export: 
      Name: "CLI:GroupArn"
    Value: !GetAtt devGroup.Arn
  accessKeyId: 
    Description: "The IAM User Access Key Id"
    Export: 
      Name: "CLI:AccessKeyId"
    Value: !Ref devAccessKey
  secretAccessKey: 
    Description: "The IAM User Secret Access Key"
    Export: 
      Name: "CLI:SecretAccessKey"
    Value: !GetAtt devAccessKey.SecretAccessKey
Parameters:
  policyArn:
    Type: String
    Default: arn:aws:iam::aws:policy/AdministratorAccess
Resources: 
  devUser:
    Type: AWS::IAM::User
    Properties: 
      Groups:
        - !Ref devGroup
      UserName: Developer1
  devGroup:
    Type: AWS::IAM::Group
    Properties:
      GroupName: Developers
      ManagedPolicyArns: 
        - !Ref policyArn
  devAccessKey:
    Type: AWS::IAM::AccessKey
    Properties: 
      UserName: !Ref devUser
  addUserToGroup:
    Type: AWS::IAM::UserToGroupAddition
    Properties:
      GroupName: !Ref devGroup
      Users:
      - !Ref devUser
EOF
) 

echo "$cfTemplate" > temp.yaml

aws s3 cp temp.yaml "s3://$bucketName"
url=$(aws s3 presign "s3://$bucketName/temp.yaml")

# Validate that the template is well formed
aws cloudformation validate-template --template-url $url

# Build the template parameter list
templateParameters="ParameterKey=policyArn,ParameterValue=$policyArn"

echo "$templateParameters"

# Create the stack. Create the stack or update the stack, not both
aws cloudformation create-stack --stack-name $stackName --template-url $url --parameters $templateParameters --disable-rollback --capabilities CAPABILITY_NAMED_IAM --tags Key=group,Value=acloud.guru

# Update stack if it already exists
aws cloudformation update-stack --stack-name $stackName --template-url $url --parameters $templateParameters --capabilities CAPABILITY_NAMED_IAM --tags Key=group,Value=acloud.guru

# Monitor the stack creation status
aws cloudformation describe-stacks | jq -r ".Stacks[].StackStatus"

# Get the stack output values
outputs=$(aws cloudformation describe-stacks | jq -c '.Stacks[].Outputs')
accessKeyId=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("accessKeyId")) | .OutputValue')
secretAccessKey=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("secretAccessKey")) | .OutputValue')
userArn=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("userArn")) | .OutputValue')
groupArn=$(echo $outputs | jq -r '.[] | select(.OutputKey | contains("groupArn")) | .OutputValue')
echo $accessKeyId $secretAccessKey $userArn $groupArn

## Cleanup

rm temp.yaml
aws s3 rm "s3://$bucketName/temp.yaml"

# Delete the stack
aws cloudformation delete-stack --stack-name $stackName
aws cloudformation describe-stacks | jq -r ".Stacks[].StackStatus"
