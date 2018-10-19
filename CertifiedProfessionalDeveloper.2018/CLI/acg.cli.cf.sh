#!/bin/bash 

### AWS CLI code and Cloudformation template for the AWS CLI lab
### from the acloud.guru AWS Certified Develper Associate course 

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

# Change to an existing bucket in the account
bucketName="acg.alb.cf"

policyArn="arn:aws:iam::aws:policy/AdministratorAccess"
stackName="acg-cli"

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
