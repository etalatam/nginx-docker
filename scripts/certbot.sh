#!/bin/bash

set -e

# Si la variable DEBUG existe, se mostraran las órdenes y sus argumentos mientras se ejecutan.
[ -n "${DEBUG:-}" ] && set -x

export DEFAULT_MAIL=${default_mail:-""}
export EXPAND=${expnad:-}
export DOMAIN=${domain:-}
export AWS_REGION=${AWS_REGION:-"us-east-1"}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}
export ALB_ARN=${ALB_ARN:-"arn:aws:elasticloadbalancing:REGION:ACCOUNT_ID:loadbalancer/app/ALB_NAME/4a1df3859a2576ca"}
export ALB_LISTENER_PORT="443"
export TARGET_GROUP_ARN=${TARGET_GROUP_ARN:-}

usage="
$(basename "$0") [-d domain] [-e expand]

Create o expand a certificated

where:
    -h  show this help text
    -d  domain name to create or expand
    -e  space separate list of domain to add to the primary domain.
    -m  mail to notify
"

while getopts ":h:d:e:m:" opt; do
  case ${opt} in

    h)
      printf $usage
      exit 1
      ;;
    d )
      DOMAIN=$OPTARG
      ;;
    e )
      EXPAND=$OPTARG
      ;;
    m )
      DEFAULT_MAIL=$OPTARG
      ;;
    \? )
      ;;
    : )
      ;;
  esac
done
shift $((OPTIND -1))

if [ -z "${DOMAIN}" ]; then
    echo "the parameter domain is missing. ${usage}"
    exit 1
fi

if [ -z "${DEFAULT_MAIL}" ]; then
    echo "the parameter default_mail is missing. ${usage}"
    exit 1
fi


if [[ -z "$EXPAND" ]]; then
    echo "Sigle domain ${DOMAIN}"
    certbot \
      certonly \
      --verbose \
      --non-interactive \
      --agree-tos \
      --webroot \
      --webroot-path=/usr/share/nginx/html/ \
      --email ${DEFAULT_MAIL} \
      --keep \
      -d ${DOMAIN}
else
    echo "Expand domain ${DOMAIN}"
    certbot \
      certonly \
      --verbose \
      --non-interactive \
      --agree-tos \
      --webroot \
      --webroot-path=/usr/share/nginx/html/ \
      --email ${DEFAULT_MAIL} \
      --expand \
      --keep \
      -d ${DOMAIN} \
      -d ${EXPAND}
fi

if [ $? -gt	 0 ]; then
  cat /var/log/letsencrypt/letsencrypt.log
  exit $?
fi

EXIST="/etc/letsencrypt/live/$DOMAIN/"
if [ -d "$EXIST" ]; then
  
  echo "Cheking [/etc/letsencrypt/live/$DOMAIN/]"

  if [ -n ${AWS_ACCESS_KEY_ID} ]; then
    echo "Importing certificate to aws acm..."

    CERT_ARN=`aws acm import-certificate --region $AWS_REGION --certificate fileb:///etc/letsencrypt/live/$DOMAIN/cert.pem --certificate-chain fileb:///etc/letsencrypt/live/$DOMAIN/fullchain.pem --private-key fileb:///etc/letsencrypt/live/$DOMAIN/privkey.pem | jq -r .CertificateArn`

    if [ -n "$CERT_ARN" ]; then

      echo "CERT_ARN: $CERT_ARN"

      # If a listener does not exist for port 443, create it
      LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'Listeners[?Port==443].ListenerArn' --output text)
      if [[ -z "$LISTENER_ARN" ]]; then
        echo "Creating listener for port 443..."
        LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol "HTTPS" --port 443 --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN --output text)
      fi

      echo "Asociando certificado al listener..."
      aws elbv2 add-listener-certificates \
        --listener-arn "$LISTENER_ARN" \
        --certificates "$CERT_ARN"
    fi
  fi
else
  echo "File [/etc/letsencrypt/live/$DOMAIN/] not found"
fi