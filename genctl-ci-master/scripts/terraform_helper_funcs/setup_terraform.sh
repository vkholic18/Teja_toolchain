#!/usr/bin/env bash

echo "Setting terraform config"

set +x

cat << EOF > ~/.terraform.d/credentials.tfrc.json
{
    "credentials": {
        "$artifactory_domain": {
            "token": "$artifactory_token"
            }
        }
}
EOF