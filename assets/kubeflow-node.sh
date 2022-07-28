#!/bin/bash

master_ip=$1

echo "start"
echo $master_ip
sed -i "s/master_ip/$master_ip/g" /assets/cert.yaml
cat /assets/cert.yaml
