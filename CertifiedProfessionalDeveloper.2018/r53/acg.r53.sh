#!/bin/bash 

### AWS CLI code for the Route 53 lab from the acloud.guru AWS
### Certified Develper Associate course 

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

domainName="anothercloudguruwebsite.com" # Must be an available domain name

firstName="john"
lastName="miller"
contactType="PERSONAL"
addressLine1="26928 Marbella"
addressLine2=""
city="mission viejo"
state="ca"
countryCode="1"
zipCode="92691"
phoneNumber="9496895051"
email="jmiller@pdata.com"
fax=""

contact="FirstName=$firstName,LastName=$lastName,ContactType=$contactType,AddressLine1=$addressLine1,AddressLine2=$addressLine2,City=$city,State=$state,CountryCode=$countryCode,ZipCode=$zipCode,PhoneNumber=$phoneNumber,Email=$email,Fax=$fax"

## Register the domain (Fails and I don't know why!?!)
operationId=$(aws route54domains register-domain --domain-name $domainName --duration-in-years 1 --no-auto-renew --admin-contact $contact --registrant-contact $contact --tech-contact $contact --privacy-protect-admin-contact --privacy-protect-registrant-contact --privacy-protect-tech-contact)

# Post domain registration

hostedZoneId=$(aws route53 list-hosted-zones-by-name --dns-name $domainName | jq -r ".HostedZones[].Id")
hostedZoneId=${hostedZoneId##/*/}
echo $hostedZoneId

canonicalHostedZoneId=$(aws elbv2 describe-load-balancers --load-balancer-arns $loadBalancerArn | jq -r ".LoadBalancers[].CanonicalHostedZoneId")
echo $canonicalHostedZoneId

# Create apex record

changeBatch=$( cat <<EOF
{
  "Comment": "Apex record set",
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "$domainName",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$canonicalHostedZoneId",
          "DNSName": "$loadBalancerDns",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
) 

echo "$changeBatch"

changeInfoId=$aws route53 change-resource-record-sets --hosted-zone-id $hostedZoneId --change-batch "$changeBatch"  | jq -r ".ChangeInfo.Id")
echo$ changeInfoId
changeInfoId=${changeInfoId##/*/}

aws route53 get-change --id $changeInfoId 

# This could take a while to propogate to your DNS. You can test it right away in the console.
curl $domainName

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
