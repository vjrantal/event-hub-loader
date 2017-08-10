# Introduction

This repository contains scripts to generate load against an Azure Event Hub and to create all necessary resources. The load is generated with wrk running within Azure Container Instances.

# Running locally

## Prerequisites

* Run `npm install` to install dependencies required by the node script
* Install the [azure-cli](https://github.com/Azure/azure-cli) and make sure the `az` binary can be found from $PATH
* Login with `az login`
* Create a resource group for the resources the scripts create with `az group create --name Travis --location "West Europe"`

## Set required environment variables

### Mandatory

```
export RESOURCE_GROUP=Travis
export WRK_SCRIPT_URL=https://gist.githubusercontent.com/vjrantal/113fa910444130d2d6431cdc84e6f80e/raw/0f67559a620647d6842c579b362a139a6b338cb1/script.lua
```

In above, the script URL can point to your custom script, but remebember to set `wrk.method = "POST"` in that script since Event Hub accepts only the POST method.

### Optional

```
export CONTAINER_COUNT=8
export PARTITION_COUNT=8
export SLEEP_IN_SECONDS=300
export WRK_OPTIONS="-t 1 -d 600s -c 50"
```

## Run

```
./run.sh
```

Observe the output that prints the Incoming Messages metric from the Event Hub created. In a success case, one should be able to see a non-zero value in the total property like in the sample output below:

```
    "data": [
      {
        "average": null,
        "count": null,
        "maximum": null,
        "minimum": null,
        "timeStamp": "2017-07-11T07:36:00+00:00",
        "total": 504874.0
      }
    ]
```
