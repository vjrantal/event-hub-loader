#!/bin/bash

set -e
set -o pipefail

KEEP_EVENT_HUB=${KEEP_EVENT_HUB:=false}
PRINT_METRICS=${PRINT_METRICS:=false}

EVENT_HUB_NAME=hubname

if [ $EXISTING_EVENT_HUB_NAMESPACE ]; then
  KEEP_EVENT_HUB=true
  NAMESPACE_NAME=$EXISTING_EVENT_HUB_NAMESPACE

  EVENT_HUB_HOST=$(az eventhubs namespace show -g $RESOURCE_GROUP -n $NAMESPACE_NAME --query "serviceBusEndpoint" -o tsv)
else
  echo "Creating the Event Hub..."
  
  NAMESPACE_NAME=$(date +%s | shasum | base64 | head -c 16)
  MIN_THROUGHPUT_UNITS=1
  MAX_THROUGHPUT_UNITS=20
  EVENT_HUB_HOST=$(az eventhubs namespace create -g $RESOURCE_GROUP -n $NAMESPACE_NAME --enable-auto-inflate --capacity $MIN_THROUGHPUT_UNITS --maximum-throughput-units $MAX_THROUGHPUT_UNITS --query "serviceBusEndpoint" -o tsv)
  
  PARTITION_COUNT=${PARTITION_COUNT:=8}
  az eventhubs eventhub create -g $RESOURCE_GROUP --namespace-name $NAMESPACE_NAME -n $EVENT_HUB_NAME --partition-count $PARTITION_COUNT > /dev/null
fi

TARGET_URL=$EVENT_HUB_HOST$EVENT_HUB_NAME/messages
IMAGE="vjrantal/wrk-with-online-script"
CONTAINER_PREFIX=$(date +%s)
CONTAINER_COUNT=${CONTAINER_COUNT:=8}

SLEEP_IN_SECONDS=${SLEEP_IN_SECONDS:=300}

# Default options is duration twice the amount of sleep
# so that the test takes at least as long as the time we
# keep the container alive
WRK_OPTIONS=${WRK_OPTIONS:="-d $((SLEEP_IN_SECONDS*2))"}

EVENT_HUB_SHARED_ACCESS_KEY_NAME=$(az eventhubs namespace authorization-rule list -g $RESOURCE_GROUP --namespace-name $NAMESPACE_NAME --query "[0].name" -o tsv)
EVENT_HUB_SHARED_ACCESS_KEY=$(az eventhubs namespace authorization-rule keys list -g $RESOURCE_GROUP --namespace-name $NAMESPACE_NAME -n $EVENT_HUB_SHARED_ACCESS_KEY_NAME --query "primaryKey" -o tsv)

# generate SAS token, by default token expires 24 hours from now
WRK_HEADER="Authorization: $(python get_sas_token.py $TARGET_URL $EVENT_HUB_SHARED_ACCESS_KEY_NAME $EVENT_HUB_SHARED_ACCESS_KEY)"
echo "Creating the Container Instances..."

COUNTER=1
while [ $COUNTER -le $CONTAINER_COUNT ]; do
  az container create --output json -g $RESOURCE_GROUP --name $CONTAINER_PREFIX$COUNTER --image "$IMAGE" --restart-policy=OnFailure -e SCRIPT_URL="$WRK_SCRIPT_URL" TARGET_URL="$TARGET_URL" WRK_OPTIONS="$WRK_OPTIONS" WRK_HEADER="$WRK_HEADER" > /dev/null
  let COUNTER=COUNTER+1
done

echo "Sleeping for ${SLEEP_IN_SECONDS} seconds..."
sleep $SLEEP_IN_SECONDS

EVENT_HUB_NAMESPACE_ID=$(az eventhubs namespace show -g $RESOURCE_GROUP -n $NAMESPACE_NAME --query "id" -o tsv)
if [[ "$PRINT_METRICS" != true && "$KEEP_EVENT_HUB" = true ]]; then
  echo -e "Get metrics with the following command:\naz monitor metrics list --output json --resource $EVENT_HUB_NAMESPACE_ID --metric incomingMessages --interval P1D"
fi

if [[ "$PRINT_METRICS" = true ]]; then
  TOTAL_MESSAGES=$(az monitor metrics list --resource $EVENT_HUB_NAMESPACE_ID --metric incomingMessages --interval P1D --query "value[0].timeseries[0].data[0].total" -o tsv)
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
  az resource delete --id $EVENT_HUB_NAMESPACE_ID || true
fi