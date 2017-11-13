#!/bin/bash
vpcName="lb-nw-final"
subnetName="subnet-us-west-1"
subnetRegion="us-west1"
cidrRangeSubnet="192.168.105.0/24"
startUpScript="gcloud/startup-script.sh"
webserverTags="webservers"
instanceTemplate="instancetemplatelb"
instanceGroupName="instancegroupuswest"
autoScalingMax="10"
autoScalingMin="1"
cpuUtilizationMax="0.75"
coolDownPeriod="60"
healthCheckName="webserver-http"
backEndServiceName="webserver-backend"
urlMapName="webserver"
targetHttpProxy="webserver-proxy"
globalAddressName="lb-ip"
globalForwardingRuleName="webserver-rule"
fwAllowHttp="allow-lb-hc-http"
# Create a custom subnetwork encompassing a region
gcloud compute networks create $vpcName --subnet-mode custom
# Create instance template using default OS( Ubunutu14.04) and start up script
gcloud compute instance-templates create $instanceTemplate --image-project ubuntu-os-cloud --machine-type="f1-micro" --network="$vpcName" --image-family="ubuntu-1404-lts" --metadata-from-file startup-script=$startUpScript --region=$subnetRegion --subnet $subnetName --tags=$webserverTags
# Create instance group from template
gcloud compute instance-groups managed create $instanceGroupName --size=1 --template=$instanceTemplate --region=$subnetRegion
# Create http health check for lb
gcloud compute health-checks create http $healthCheckName --check-interval 3 --port 80 --timeout 3 --unhealthy-threshold 2
# create auto scaling groups
gcloud compute instance-groups managed set-autoscaling $instanceGroupName --max-num-replicas $autoScalingMax --min-num-replicas $autoScalingMin --target-cpu-utilization $cpuUtilizationMax --cool-down-period $coolDownPeriod --region $subnetRegion
# create named ports for load balancing
gcloud compute instance-groups managed set-named-ports $instanceGroupName --named-ports http:80 --region $subnetRegion
# Create backend service for lb
gcloud compute backend-services create $backEndServiceName --protocol HTTP --health-checks $healthCheckName --global --port-name http --protocol HTTP --timeout=10s
# Adding instance groups to backend service
gcloud compute backend-services add-backend $backEndServiceName --instance-group=$instanceGroupName --balancing-mode=UTILIZATION  --capacity-scaler=1.0 --max-utilization=$cpuUtilizationMax   --global --instance-group-region=$subnetRegion
# Create url map for lb
gcloud compute url-maps create $urlMapName --default-service $backEndServiceName
# Create http proxy for lb
gcloud compute target-http-proxies create $targetHttpProxy --url-map $urlMapName
# Creating a global ip address for lb(IPV4)
gcloud compute addresses create $globalAddressName --ip-version=IPV4 --global
# Just in case
sleep 5
# Fetching the previously created ip address
globalIp=`gcloud compute addresses describe $globalAddressName --global | grep '^address:' | sed 's/ *//g' | awk -F: '{ print $NF }'`
# Adding forwarding rules for load balancer
gcloud compute forwarding-rules create $globalForwardingRuleName --address $globalIp --global --target-http-proxy $targetHttpProxy --ports 80
# Adding firewalls for access to port 80 from load balancer and health checking service
gcloud compute firewall-rules create $fwAllowHttp --source-ranges 130.211.0.0/22,35.191.0.0/16 --target-tags $webserverTags --allow tcp:80 --network $vpcName
echo $globalIp
