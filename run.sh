#!/bin/bash

set -e
set -o pipefail

KEEP_EVENT_HUB=${KEEP_EVENT_HUB:=false}
PRINT_METRICS=${PRINT_METRICS:=false}

if [ $EXISTING_EVENT_HUB ]; then
  KEEP_EVENT_HUB=true
  EVENT_HUB_CONNECTION=$EXISTING_EVENT_HUB
else
  echo "Creating the Event Hub..."
  PARTITION_COUNT=${PARTITION_COUNT:=8}
  NAMESPACE_NAME=$(date +%s | shasum | base64 | head -c 16)
  CREATE_OUTPUT=$(az group deployment create --output json --resource-group $RESOURCE_GROUP --template-file azuredeploy.json --name $NAMESPACE_NAME --parameters namespaceName=$NAMESPACE_NAME partitionCount=$PARTITION_COUNT)

  EVENT_HUB_CONNECTION=$(echo $CREATE_OUTPUT | jq -r ".properties.outputs.connectionString.value")

  EVENT_HUB_ID=$(echo $CREATE_OUTPUT | jq -r ".id")
  EVENT_HUB_ID="${EVENT_HUB_ID/Microsoft.Resources\/deployments/Microsoft.EventHub\/namespaces}"
fi

EVENT_HUB_HOST=$(echo $(echo $EVENT_HUB_CONNECTION | cut -d";" -f1) | cut -d"/" -f3)
EVENT_HUB_PATH=$(echo $(echo $EVENT_HUB_CONNECTION | cut -d";" -f4) | cut -d"=" -f2)
TARGET_URL=https://$EVENT_HUB_HOST/$EVENT_HUB_PATH/messages

IMAGE="vjrantal/wrk-with-online-script"
CONTAINER_PREFIX=$(date +%s)
CONTAINER_COUNT=${CONTAINER_COUNT:=8}

SLEEP_IN_SECONDS=${SLEEP_IN_SECONDS:=300}

# Default options is duration twice the amount of sleep
# so that the test takes at least as long as the time we
# keep the container alive
WRK_OPTIONS=${WRK_OPTIONS:="-d $((SLEEP_IN_SECONDS*2))"}

EVENT_HUB_SHARED_ACCESS_KEY_NAME=$(echo $(echo $EVENT_HUB_CONNECTION | cut -d";" -f2) | cut -d"=" -f2)

EVENT_HUB_SHARED_ACCESS_KEY=$(echo $EVENT_HUB_CONNECTION | cut -d";" -f3)
EVENT_HUB_SHARED_ACCESS_KEY=${EVENT_HUB_SHARED_ACCESS_KEY#SharedAccessKey=}

# generate SAS token, by default token expires 24 hours from now
source get-sas-token.sh
WRK_HEADER="Authorization: $(get_sas_token $TARGET_URL $EVENT_HUB_SHARED_ACCESS_KEY_NAME $EVENT_HUB_SHARED_ACCESS_KEY)"

echo "Creating the Container Instances..."

COUNTER=1
while [ $COUNTER -le $CONTAINER_COUNT ]; do
  az container create --output json -g $RESOURCE_GROUP --name $CONTAINER_PREFIX$COUNTER --image "$IMAGE" -e SCRIPT_URL="$WRK_SCRIPT_URL" TARGET_URL="$TARGET_URL" WRK_OPTIONS="$WRK_OPTIONS" WRK_HEADER="$WRK_HEADER" > /dev/null
  let COUNTER=COUNTER+1
done

echo "Sleeping for ${SLEEP_IN_SECONDS} seconds..."
sleep $SLEEP_IN_SECONDS

# for metrics, if you reused an existing event hub by exporting EXISTING_EVENT_HUB, please also export the corresponding EVENT_HUB_ID (format: /subscriptions/.../resourceGroups/.../providers/Microsoft.EventHub/namespaces/...)
if [[ $EVENT_HUB_ID && "$PRINT_METRICS" != true && "$KEEP_EVENT_HUB" = true ]]; then
  echo -e "Get metrics with the following command:\naz monitor metrics list --output json --resource $EVENT_HUB_ID --metric incomingMessages --interval P1D"
fi

if [[ $EVENT_HUB_ID && "$PRINT_METRICS" = true ]]; then
  METRICS_OUTPUT=$(az monitor metrics list --output json --resource $EVENT_HUB_ID --metric incomingMessages --interval P1D)
  TOTAL_MESSAGES=$(echo $METRICS_OUTPUT | jq -r ".value[0].timeseries[0].data[0].total")
  echo "The Event Hub currently has $TOTAL_MESSAGES incoming messages"
fi

echo "Removing the Container Instances..."

COUNTER=1
while [ $COUNTER -le $CONTAINER_COUNT ]; do
  az container delete -g $RESOURCE_GROUP --name $CONTAINER_PREFIX$COUNTER --yes > /dev/null
  let COUNTER=COUNTER+1
done

if [ "$KEEP_EVENT_HUB" = true ]; then
  echo "The Event Hub was not removed..."
else
  echo "Removing the Event Hub..."
  # Ignore the return value of above command, because sometimes error value is
  # returned even when the resource deletion succeeds.
  az resource delete --id $EVENT_HUB_ID || true
fi