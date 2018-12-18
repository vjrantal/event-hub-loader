# Introduction

This repository contains scripts to generate load against an Azure Event Hub and to create all necessary resources. The load is generated with wrk running within Azure Container Instances (ACI).

It was tested that with 20 ACI and with 2KB payload, it was possible to ingest 42572 messages per second. In terms of data, this means approximately 85 MB/s when the maximum allowed by the 100 Throughput Units would have been 100 MB/s.

You can take a look at the [CI configuration file](.travis.yml) to see how to setup and install the dependencies in the CI. The latest CI build output can be seen by clicking the badge below:

[![Build Status](https://travis-ci.org/vjrantal/event-hub-loader.svg?branch=master)](https://travis-ci.org/vjrantal/event-hub-loader)

For more details and some background information about this project, see the blog post at [https://blog.vjrantal.net/2017/08/10/load-testing-with-azure-container-instances-and-wrk/](https://blog.vjrantal.net/2017/08/10/load-testing-with-azure-container-instances-and-wrk/).

# Running locally

## Prerequisites

* Install the [azure-cli](https://github.com/Azure/azure-cli) and make sure the `az` binary can be found from $PATH
* Login with `az login`
* Create a resource group for the resources the scripts create with `az group create --name Travis --location "West Europe"`
* remove default location you may have configured with `az configure --defaults location=''`

## Set required environment variables

### Mandatory

```
export RESOURCE_GROUP=Travis
export WRK_SCRIPT_URL=https://gist.githubusercontent.com/vjrantal/113fa910444130d2d6431cdc84e6f80e/raw/0f67559a620647d6842c579b362a139a6b338cb1/script.lua
```

In above, the script URL can point to your custom script, but do set `wrk.method = "POST"` in that script since Event Hub accepts only the POST method.

### Optional

```
export CONTAINER_COUNT=8
export PARTITION_COUNT=8
export SLEEP_IN_SECONDS=300
export WRK_OPTIONS="-t 1 -d 600s -c 50"
export KEEP_EVENT_HUB=true
export EXISTING_EVENT_HUB_NAMESPACE=sample-namespace
export EVENT_HUB_NAME=sample-hub
export PRINT_METRICS=true
```

## Run

```
./run.sh
```

If you have set `PRINT_METRICS=true`, you can observe the output that prints the Incoming Messages metric from the Event Hub created. In a success case, one should be able to see a an output like below that informs about more than zero incoming messages:

```
The Event Hub currently has 504874.0 incoming messages
```