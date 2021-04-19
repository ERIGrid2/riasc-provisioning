#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

docker run --volume ${DIR}/..:/provisioning --rm quay.io/coreos/butane:release --help --files-dir=/provisioning < butane.yaml > butane.ign
