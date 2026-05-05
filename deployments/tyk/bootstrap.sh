#!/bin/bash


source scripts/common.sh
deployment="Tyk"

log_start_deployment
bootstrap_progress

log_message "Setting global variables"
dashboard_base_url="http://tyk-dashboard.localhost:$(jq -r '.listen_port' deployments/tyk/volumes/tyk-dashboard/tyk_analytics.conf)"
DASHBOARD_DISPLAY_URL="$dashboard_base_url"
gateway_base_url="http://$(jq -r '.host_config.override_hostname' deployments/tyk/volumes/tyk-dashboard/tyk_analytics.conf)"
GATEWAY_DISPLAY_URL="$gateway_base_url"
set_context_data "1" "gateway" "1" "base-url" $gateway_base_url
gateway_base_url_tcp="tyk-gateway.localhost:8086"
GATEWAY_DISPLAY_URL_TCP="$gateway_base_url_tcp"
log_ok
bootstrap_progress

log_message "Checking Dashboard licence exists"
if ! grep -q "DASHBOARD_LICENCE=" .env; then
  log_message "ERROR: Dashboard licence missing from Docker environment file (.env). Add a licence to the DASHBOARD_LICENCE environment variable."
  exit 1
fi
if grep -q "DASHBOARD_LICENCE=add_your_dashboard_licence_here" .env; then
  log_message "ERROR: Placeholder Dashboard licence found in Docker environment file (.env). Replace \"add_your_dashboard_licence_here\" with your Tyk licence."
  exit 1
fi
log_ok
bootstrap_progress

log_message "Checking Dashboard licence expiry"
licence_days_remaining=0
check_licence_expiry "DASHBOARD_LICENCE"; expiry_check=$?
if [[ "$expiry_check" -eq "1" ]]; then
  # The error message is now displayed by the check_licence_expiry function itself
  exit 1
fi
dashboard_licence_days_remaining=$licence_days_remaining
bootstrap_progress

log_message "Getting Dashboard configuration"
dashboard_admin_api_credentials=$(cat deployments/tyk/volumes/tyk-dashboard/tyk_analytics.conf | jq -r .admin_secret 2>> logs/bootstrap.log)
log_message "  Dashboard Admin API Credentials = $dashboard_admin_api_credentials"
portal_root_path=$(cat deployments/tyk/volumes/tyk-dashboard/tyk_analytics.conf | jq -r .host_config.portal_root_path 2>> logs/bootstrap.log)
gateway_api_credentials=$(cat deployments/tyk/volumes/tyk-gateway/tyk.conf | jq -r .secret)
bootstrap_progress

# Check whether this script is being run in a container
log_message "Checking for containerised runner environment"
if [ "$CONTAINERISED_RUNNER" == "true" ]; then
  log_message "  Running on container"
  # Get the runner container's hostname
  RUNNER_ID=$(hostname)

  # Wait for network to exist
  NETWORK_NAME="tyk-demo_tyk"
  TIMEOUT=10
  until docker network inspect "$NETWORK_NAME" > /dev/null 2>&1 || [ $TIMEOUT -eq 0 ]; do
    log_message "  Waiting for network $NETWORK_NAME to be created..."
    bootstrap_progress
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
  done

  # Connect the runner container to the network
  docker network connect "$NETWORK_NAME" "$RUNNER_ID"

  if [ $? -eq 0 ]; then
    log_message "  Successfully connected the runner container $RUNNER_ID to the network $NETWORK_NAME"
  else
    echo "ERROR: Failed to connect the runner container $RUNNER_ID to the network $NETWORK_NAME"
    exit 1
  fi

  # Redefine the base URLs, such that the services can be accessed from the container running this script
  gateway_base_url="http://tyk-gateway:8080"
  dashboard_base_url="http://tyk-dashboard:3000"
  set_context_data "1" "gateway" "1" "base-url" $gateway_base_url
else
  log_message "  Running on host - no further action required"
fi
log_ok
bootstrap_progress

# Certificates

log_message "Checking for existing OpenSSL container"
OPENSSL_CONTAINER_NAME="tyk-demo-openssl"
if [ "$(docker ps -a --format '{{.Names}}' | grep -w "$OPENSSL_CONTAINER_NAME" | wc -l)" -gt 0 ]; then
  log_message "Removing existing OpenSSL container $OPENSSL_CONTAINER_NAME"
  docker rm -f $OPENSSL_CONTAINER_NAME > /dev/null
else
  log_ok
fi
bootstrap_progress

log_message "Creating temporary container $OPENSSL_CONTAINER_NAME for OpenSSL usage"
docker run -d --name $OPENSSL_CONTAINER_NAME \
  -v tyk-mcp-lab_tyk-gateway-certs:/tyk-gateway-certs \
  -v tyk-mcp-lab_tyk-dashboard-certs:/tyk-dashboard-certs \
  alpine:3.20.1 tail -f /dev/null >/dev/null 2>&1
log_ok
bootstrap_progress

log_message "Install OpenSSL into container $OPENSSL_CONTAINER_NAME"
docker exec $OPENSSL_CONTAINER_NAME apk add --no-cache openssl >/dev/null 2>>logs/bootstrap.log
# Wait for the installation to complete
while true; do
    # Check if OpenSSL is installed by trying to get its version
    if docker exec $OPENSSL_CONTAINER_NAME openssl version >/dev/null 2>&1; then
        log_message "  OpenSSL has been successfully installed"
        break
    else
        log_message "  Waiting for OpenSSL to be installed..."
        sleep 2
    fi
done

log_message "OpenSSL version used for generating certs: $(docker exec $OPENSSL_CONTAINER_NAME openssl version)"

log_message "Generating private key for secure messaging and signing"
docker exec $OPENSSL_CONTAINER_NAME sh -c "openssl genrsa -out /tyk-dashboard-certs/private-key.pem 2048" >/dev/null 2>>logs/bootstrap.log
if [ "$?" -ne "0" ]; then
  echo "ERROR: Could not generate private key"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Flushing writes on OpenSSL container $OPENSSL_CONTAINER_NAME"
docker exec $OPENSSL_CONTAINER_NAME sync
log_ok
bootstrap_progress

log_message "Checking private key exists"
docker exec $OPENSSL_CONTAINER_NAME sh -c "test -r /tyk-dashboard-certs/private-key.pem"
if [ "$?" -ne "0" ]; then
  echo "ERROR: Could not read /tyk-dashboard-certs/private-key.pem"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Generating public key for secure messaging and signing"
docker exec $OPENSSL_CONTAINER_NAME sh -c "openssl rsa -in /tyk-dashboard-certs/private-key.pem -pubout -out /tyk-gateway-certs/public-key.pem" >/dev/null 2>>logs/bootstrap.log
if [ "$?" -ne "0" ]; then
  echo "ERROR: Could not generate public key"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Flushing writes on OpenSSL container $OPENSSL_CONTAINER_NAME"
docker exec $OPENSSL_CONTAINER_NAME sync
log_ok
bootstrap_progress

log_message "Checking public key exists"
docker exec $OPENSSL_CONTAINER_NAME sh -c "test -r /tyk-gateway-certs/public-key.pem"
if [ "$?" -ne "0" ]; then
  echo "ERROR: Could not read /tyk-gateway-certs/public-key.pem"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Setting read and execute permissions on certificate volumes"
docker exec $OPENSSL_CONTAINER_NAME chmod -R a+rX /tyk-gateway-certs >/dev/null 2>>logs/bootstrap.log
if [ "$?" != "0" ]; then
  echo "ERROR: Could not set read permissions on /tyk-gateway-certs volume"
  exit 1
fi
docker exec $OPENSSL_CONTAINER_NAME chmod -R a+rX /tyk-dashboard-certs >/dev/null 2>>logs/bootstrap.log
if [ "$?" != "0" ]; then
  echo "ERROR: Could not set read permissions on /tyk-dashboard-certs volume"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Flushing writes on OpenSSL container $OPENSSL_CONTAINER_NAME"
docker exec $OPENSSL_CONTAINER_NAME sync
log_ok
bootstrap_progress

log_message "Recreating containers to load new certificates"
eval $(generate_docker_compose_command) up -d --no-deps --force-recreate tyk-dashboard
eval $(generate_docker_compose_command) up -d --no-deps --force-recreate tyk-gateway
log_ok

log_message "Wait for services to be available after restart"
wait_for_liveness "$gateway_base_url/hello"

log_message "Removing temporary OpenSSL container $OPENSSL_CONTAINER_NAME"
docker rm -f $OPENSSL_CONTAINER_NAME >/dev/null 2>>logs/bootstrap.log
if [ "$?" != "0" ]; then
  echo "ERROR: Could not remove temporary OpenSSL container $OPENSSL_CONTAINER_NAME"
  exit 1
fi
log_ok
bootstrap_progress

# Dashboard Data

log_message "Wait for services to be ready before importing data"
wait_for_liveness "$gateway_base_url/hello"

# The order these are processed in is important, due to dependencies between objects
log_message "Processing Dashboard Data"
for data_group_path in deployments/tyk/data/tyk-dashboard/*; do
  if [[ -d $data_group_path ]]; then
    log_message "Processing data in $data_group_path"
    data_group="${data_group_path##*/}"

    # Organisation
    log_message "Creating Organisation"
    organisation_data_path="$data_group_path/organisation.json"
    if [[ ! -f $organisation_data_path ]]; then
          log_message "ERROR: organisation file missing: $organisation_data_path"
          exit 1
    fi
    create_organisation "$organisation_data_path" "$dashboard_admin_api_credentials" "$data_group" "1"
    bootstrap_progress
    organisation_id=$(get_context_data "$data_group" "organisation" "1" "id")

    # Dashboard Users
    log_message "Creating Dashboard Users"
    index=1
    admin_user_index=-1
    for file in $data_group_path/users/*; do
      if [[ -f $file ]]; then
        create_dashboard_user "$file" "$dashboard_admin_api_credentials" "$data_group" "$index"
        is_admin="$(jq -r '.user_permissions.IsAdmin' $file)"
        if [[ "$is_admin" == "admin" ]]; then
          admin_user_index=$index
        fi
        index=$((index + 1))
        bootstrap_progress
      fi

      if [ "$admin_user_index" -eq "-1" ]; then
        log_message "ERROR: No Dashboard admin user found in data group $data_group_path"
        exit 1
      fi
    done
    log_message "  Dashboard admin user index: $admin_user_index"

    # get admin user dashboard API key for Dashboard API calls
    dashboard_user_api_key=$(get_context_data "$data_group" "dashboard-user" "$admin_user_index" "api-key")

    # User Groups
    log_message "Creating Dashboard User Groups"
    index=1
    for file in $data_group_path/user-groups/*; do
      if [[ -f $file ]]; then
        create_user_group "$file" "$dashboard_user_api_key" "$data_group" "$index"
        index=$((index + 1))
        bootstrap_progress
      fi
    done

    # Webhooks
    log_message "Creating Webhooks"
    for file in $data_group_path/webhooks/*; do
      if [[ -f $file ]]; then
        create_webhook "$file" "$dashboard_user_api_key"
        bootstrap_progress
      fi
    done

    # Certificates
    log_message "Creating Certificates"
    for file in $data_group_path/certs/*; do
      if [[ -f $file ]]; then
        create_cert "$file" "$dashboard_user_api_key"
        bootstrap_progress
      fi
    done

    # APIs
    log_message "Creating APIs"
    for file in $data_group_path/apis/*; do
      if [[ -f $file ]]; then
        if api_has_section "$file" "x-tyk-streaming" && ! licence_has_scope "DASHBOARD_LICENCE" "streams"; then
          log_message "  Warning: API $file has Tyk Streaming enabled, but the licence does not have the 'streams' scope. Skipping import."
          continue
        fi
        create_api "$file" "$dashboard_user_api_key"
        bootstrap_progress
      fi
    done

  fi
done

# System

log_message "Restarting Dashboard container to ensure Portal URLs are loaded ok"
eval $(generate_docker_compose_command) restart tyk-dashboard 1> /dev/null 2>> logs/bootstrap.log
if [ "$?" != 0 ]; then
  echo "Error occurred when restarting Dashboard container"
  exit 1
fi
log_ok
bootstrap_progress

log_message "Reloading Gateways"
hot_reload "$gateway_base_url" "$gateway_api_credentials" "group"
bootstrap_progress
wait_for_liveness "$gateway_base_url/hello"

log_end_deployment

NOCOLOUR='\033[0m'
CYAN='\033[0;36m'

echo -e "\033[2K

              ▓▓▓▓▓▓▓▓▓▓▓▓▓          ▓▓▓
                   ▓▓▓               ▓▓▓
        ${CYAN}▓▓▓▓▓${NOCOLOUR}      ▓▓▓  ▓▓▓     ▓▓▓  ▓▓▓     ▓▓
        ${CYAN}▓▓▓▓▓▓▓${NOCOLOUR}    ▓▓▓  ▓▓▓     ▓▓▓  ▓▓▓    ▓▓
          ${CYAN}▓▓▓▓▓${NOCOLOUR}    ▓▓▓  ▓▓▓     ▓▓▓  ▓▓▓▓▓▓▓▓▓
                   ▓▓▓  ▓▓▓     ▓▓▓  ▓▓▓    ▓▓ 
                   ▓▓▓   ▓▓▓▓▓▓▓▓▓▓  ▓▓▓     ▓▓
                                ▓▓▓  
                         ▓▓▓▓▓▓▓▓▓

▼ Tyk
  ▽ Dashboard ($(get_service_image_tag "tyk-dashboard"))
                Licence : $dashboard_licence_days_remaining days remaining
                    URL : $DASHBOARD_DISPLAY_URL
       Admin API Header : admin-auth
          Admin API Key : $dashboard_admin_api_credentials 
   Dashboard API Header : Authorization       
    ▾ $(get_context_data "1" "organisation" "1" "name") Organisation
               Username : $(get_context_data "1" "dashboard-user" "1" "email")
               Password : $(get_context_data "1" "dashboard-user" "1" "password")
      Dashboard API Key : $(get_context_data "1" "dashboard-user" "1" "api-key")
    ▾ $(get_context_data "2" "organisation" "1" "name") Organisation
               Username : $(get_context_data "2" "dashboard-user" "1" "email")
               Password : $(get_context_data "2" "dashboard-user" "1" "password")
      Dashboard API Key : $(get_context_data "2" "dashboard-user" "1" "api-key")
    ▾ Multi-Organisation User
               Username : $(get_context_data "1" "dashboard-user" "2" "email")
               Password : $(get_context_data "1" "dashboard-user" "2" "password")
  ▽ Gateway ($(get_service_image_tag "tyk-gateway"))
                    URL : $GATEWAY_DISPLAY_URL
               URL(TCP) : $GATEWAY_DISPLAY_URL_TCP
     Gateway API Header : x-tyk-authorization
        Gateway API Key : $gateway_api_credentials"
