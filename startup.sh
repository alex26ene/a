
REGION_1="us-central1"
REGION_2="us-east1"
ZONE_1="${REGION_1}-a" # Example zone in Region 1
ZONE_2="${REGION_2}-b" # Example zone in Region 2


gcloud compute instance-templates create Region-1-template \
    --machine-type=e2-micro \
    --network=default \
    --subnet=default \
    --tags=http-server \
    --metadata-from-file=startup-script=startup.sh \
    --description="Instance template for Region 1"

gcloud compute instance-templates create Region-2-template \
    --machine-type=e2-micro \
    --network=default \
    --subnet=default \
    --tags=http-server \
    --metadata-from-file=startup-script=startup.sh \
    --description="Instance template for Region 2"

# Create the managed instance group for Region 1
gcloud compute instance-groups managed create Region-1-mig \
    --template=Region-1-template \
    --base-instance-name=Region-1-mig \
    --size=1 \
    --zone="${ZONE_1}" \
    --autoscaling-on \
    --target-cpu-utilization=0.8 \
    --min-replicas=1 \
    --max-replicas=2 \
    --initial-delay-sec=45

# Create the managed instance group for Region 2
gcloud compute instance-groups managed create Region-2-mig \
    --template=Region-2-template \
    --base-instance-name=Region-2-mig \
    --size=1 \
    --zone="${ZONE_2}" \
    --autoscaling-on \
    --target-cpu-utilization=0.8 \
    --min-replicas=1 \
    --max-replicas=2 \
    --initial-delay-sec=45
	
	# Create the health check for the backend service
gcloud compute health-checks create tcp http-health-check \
    --port=80 \
    --check-interval=5s \
    --timeout=5s \
    --unhealthy-threshold=2 \
    --healthy-threshold=2

# Create the backend service
gcloud compute backend-services create http-backend \
    --protocol=HTTP \
    --health-checks=http-health-check \
    --global \
    --enable-logging \
    --logging-sample-rate=1.0

# Add Region 1 MIG to the backend service
gcloud compute backend-services add-backend http-backend \
    --instance-group=Region-1-mig \
    --instance-group-zone="${ZONE_1}" \
    --balancing-mode=RATE \
    --max-rate-per-instance=50 \
    --capacity-scaler=1.0 \
    --global

# Add Region 2 MIG to the backend service
gcloud compute backend-services add-backend http-backend \
    --instance-group=Region-2-mig \
    --instance-group-zone="${ZONE_2}" \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --capacity-scaler=1.0 \
    --global

# Create the URL map
gcloud compute url-maps create web-map \
    --default-service=http-backend

# Create the HTTP proxy
gcloud compute target-http-proxies create http-proxy \
    --url-map=web-map

# Create the forwarding rule for IPv4
gcloud compute forwarding-rules create http-lb-ipv4-rule \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --network-tier=PREMIUM \
    --address-region="" \
    --global \
    --target-http-proxy=http-proxy \
    --ports=80 \
    --ip-version=IPV4

# Create the forwarding rule for IPv6
gcloud compute forwarding-rules create http-lb-ipv6-rule \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --network-tier=PREMIUM \
    --address-region="" \
    --global \
    --target-http-proxy=http-proxy \
    --ports=80 \
    --ip-version=IPV6
	
	
	# Get the external IP of the IPv4 Load Balancer (run after LB creation)
gcloud compute forwarding-rules describe http-lb-ipv4-rule --global --format="value(IPAddress)"

# Get the external IP of the IPv6 Load Balancer (run after LB creation)
gcloud compute forwarding-rules describe http-lb-ipv6-rule --global --format="value(IPAddress)"

# Create the siege VM (replace ZONE_3 with a zone in your chosen Region 3)
REGION_3="us-west1" # Example Region 3
ZONE_3="${REGION_3}-a" # Example zone in Region 3

gcloud compute instances create siege-vm \
    --machine-type=e2-medium \
    --zone="${ZONE_3}" \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --scopes=https://www.googleapis.com/auth/cloud-platform



# Get the external IP of the siege-vm (run after siege-vm creation)
SIEGE_IP=$(gcloud compute instances describe siege-vm --zone="${ZONE_3}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo "SIEGE_IP: $SIEGE_IP"

# Create the Cloud Armor security policy
gcloud compute security-policies create denylist-siege \
    --description="Denylist policy for siege-vm" \
    --default-action=ALLOW

# Add the denylist rule for siege-vm IP
gcloud compute security-policies rules create 1000 \
    --security-policy=denylist-siege \
    --expression="origin.ip == '$SIEGE_IP'" \
    --action=deny \
    --description="Deny traffic from siege-vm IP" \
    --enforce-on-key=IP

# Attach the security policy to the backend service
gcloud compute backend-services update http-backend \
    --security-policy=denylist-siege \
    --global
