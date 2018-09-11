#!/bin/bash
set -e -u -o pipefail

## https://help.replicated.com/docs/kb/developer-resources/automate-install/

proxy=""

if test -e "/run/proxy-url"; then
    proxy="$(cat /run/proxy-url)"

    if test -n "$proxy"; then
        export http_proxy=$proxy
        export https_proxy=$proxy
    fi
fi

## sql script file created via cloud-init
postgres_url=$( jq -r '"postgres://" + .pg_user.value + ":" + .pg_password.value + "@" + .pg_netloc.value + "/" + .pg_dbname.value + "?" + .pg_extra_params.value' /etc/replicated-ptfe.conf )
psql -f /var/lib/ptfe-create-schemas.sql "${postgres_url}"

replicated_installer_args=(
    fast-timeouts

    ## default operator_tags is 'local', and that's insufficient given our Workers component tag requirement
    ## https://hashicorp.slack.com/archives/C7CR5NZFV/p1513715324000010
    "tags=workers"
)

if test -n "$proxy"; then
    replicated_installer_args+=("http-proxy=${proxy}")
    if test -e "/run/no-proxy"; then
        replicated_installer_args+=("additional-no-proxy=$(cat /run/no-proxy)")
    fi
else
    replicated_installer_args+=(no-proxy)
fi

echo "Running installer with options:" "${replicated_installer_args[@]}"

curl -sfSL https://get.replicated.com/docker | bash -s "${replicated_installer_args[@]}"

usermod -a -G docker ubuntu
