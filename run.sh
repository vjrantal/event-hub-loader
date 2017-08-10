#!/bin/bash

set -e
set -o pipefail

echo "Creating the Event Hub..."

PARTITION_COUNT=${PARTITION_COUNT:=8}
NAMESPACE_NAME=$(date +%s | shasum | base64 | head -c 16)
CREATE_OUTPUT=$(az group deployment create --resource-group $RESOURCE_GROUP --template-file azuredeploy.json --parameters namespaceName=$NAMESPACE_NAME partitionCount=$PARTITION_COUNT)

export EVENT_HUB_CONNECTION=$(echo $CREATE_OUTPUT | python -c '
import sys, json
output = json.load(sys.stdin)
print output["properties"]["outputs"]["connectionString"]["value"]
')

export EVENT_HUB_ID=$(export NAMESPACE_NAME=$NAMESPACE_NAME; echo $CREATE_OUTPUT | python -c '
import sys, json, os
output = json.load(sys.stdin)
print "%s/providers/Microsoft.EventHub/namespaces/%s" % ("/".join(output["id"].split("/")[:5]), os.environ["NAMESPACE_NAME"])
')

TARGET_URL=$(node -e "require('./index.js').printUrl()")

IMAGE="vjrantal/wrk-with-online-script"
CONTAINER_PREFIX=$(date +%s)
CONTAINER_COUNT=${CONTAINER_COUNT:=8}

SLEEP_IN_SECONDS=${SLEEP_IN_SECONDS:=300}

# Default options is duration twice the amount of sleep
# so that the test takes at least as long as the time we
# keep the container alive
WRK_OPTIONS=${WRK_OPTIONS:="-d $((SLEEP_IN_SECONDS*2))"}
WRK_HEADER=$(node -e "require('./index.js').printHeader()")

echo "Creating the Container Instances..."

COUNTER=1
while [ $COUNTER -le $CONTAINER_COUNT ]; do
  az container create -g $RESOURCE_GROUP --name $CONTAINER_PREFIX$COUNTER --image "$IMAGE" -e SCRIPT_URL="$WRK_SCRIPT_URL" TARGET_URL="$TARGET_URL" WRK_OPTIONS="$WRK_OPTIONS" WRK_HEADER="$WRK_HEADER" > /dev/null 2>&1
  let COUNTER=COUNTER+1
done

echo "Sleeping for ${SLEEP_IN_SECONDS} seconds..."
sleep $SLEEP_IN_SECONDS

METRICS_OUTPUT=$(az monitor metrics list --resource $EVENT_HUB_ID --metric-names EHINMSGS --time-grain P1M)
echo $(echo $METRICS_OUTPUT | python -c '
import sys, json
output = json.load(sys.stdin)
print "The Event Hub currently has %s incoming messages" % (output[0]["data"][0]["total"])
')

echo "Removing the Container Instances..."

COUNTER=1
while [ $COUNTER -le $CONTAINER_COUNT ]; do
  az container delete -g $RESOURCE_GROUP --name $CONTAINER_PREFIX$COUNTER --yes > /dev/null 2>&1
  let COUNTER=COUNTER+1
done

echo "Removing the Event Hub..."

az resource delete --id $EVENT_HUB_ID
