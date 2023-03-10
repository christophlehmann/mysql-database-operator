#!/usr/bin/env bash
set -e

source /hooks/common/functions.sh

CURRENT_OBJECT=$(mktemp)
trap "rm -rf $CURRENT_OBJECT" exit

hook::config() {
cat <<EOF
{
    "configVersion":"v1",
    "kubernetes":[{
        "apiVersion": "k8s.networkteam.com/v1",
        "kind": "MySQL57Database",
        "executeHookOnEvent": [
            "Added",
            "Modified"
        ]
    }]
}
EOF
}

hook::trigger() {
    local TYPE=$(jq -r '.[0].type' $BINDING_CONTEXT_PATH)

    if [[ $TYPE == "Synchronization" ]]
    then
        local ARRAY_COUNT=$(jq -r '.[].objects | length-1' $BINDING_CONTEXT_PATH)
        local INDEX
        for INDEX in $(seq 0 $ARRAY_COUNT)
        do
            jq -r ".[].objects[$INDEX].object" $BINDING_CONTEXT_PATH > $CURRENT_OBJECT
            handle_current_object
        done
    elif [[ $TYPE == "Event" ]]
    then
        jq -r '.[0].object' $BINDING_CONTEXT_PATH > $CURRENT_OBJECT
        handle_current_object
    fi
}

function handle_current_object() {
    local NAME=$(jq -r '.metadata.name' $CURRENT_OBJECT)
    local NAMESPACE=$(jq -r '.metadata.namespace' $CURRENT_OBJECT)
    local KIND=$(jq -r ".kind" $CURRENT_OBJECT)
    local SERVICE_NAME=$(jq -r ".spec.serviceName" $CURRENT_OBJECT)
    local SECRET_NAME=$(jq -r ".spec.secretName" $CURRENT_OBJECT)
    local DATABASE=$(echo "${NAMESPACE}_${NAME}" | sed -e 's/-//g' | cut -c -32)

    local MYSQL_USER=$(kubectl -n $NAMESPACE get secret $SECRET_NAME -o=jsonpath='{.data.user}' | base64 -d 2>/dev/null)
    local MYSQL_PASSWORD=$(kubectl -n $NAMESPACE get secret $SECRET_NAME -o=jsonpath='{.data.password}' | base64 -d 2>/dev/null)
    local DATABASE=$(kubectl -n $NAMESPACE get secret $SECRET_NAME -o=jsonpath='{.data.database}' | base64 -d 2>/dev/null)

    if common::should_be_deleted $CURRENT_OBJECT
    then
        if ! common::has_finalizer $CURRENT_OBJECT
        then
          return
        fi

        common::log $NAMESPACE $NAME "Delete database user"
        if [ ! -z "$MYSQL_USER" ]
        then
            mysql -u ${MYSQL_ADMIN_USER} -p"${MYSQL_ADMIN_PASSWORD}" -h ${MYSQL_HOST} -e "DROP USER IF EXISTS ${MYSQL_USER};"
        fi

        common::log $NAMESPACE $NAME "Delete database"
        if [ ! -z "$DATABASE" ]
        then
            mysql -u ${MYSQL_ADMIN_USER} -p"${MYSQL_ADMIN_PASSWORD}" -h ${MYSQL_HOST} -e "DROP DATABASE IF EXISTS ${DATABASE};"
        fi

        common::log $NAMESPACE $NAME "Delete service"
        kubectl -n $NAMESPACE delete service $SERVICE_NAME &>/dev/null

        common::log $NAMESPACE $NAME "Delete secret"
        kubectl -n $NAMESPACE delete secret $SECRET_NAME &>/dev/null

        common::log $NAMESPACE $NAME "Delete finalizer"
        common::remove_finalizer $CURRENT_OBJECT
        return
    fi

    if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$DATABASE" ]
    then
        common::log $NAMESPACE $NAME "Create secret"
        if [ -z "$MYSQL_USER" ]
        then
            MYSQL_USER=$(echo "${DATABASE}$(pwgen 32 1)" | cut -c -32)
        fi
        if [ -z "$MYSQL_PASSWORD" ]
        then
            MYSQL_PASSWORD=$(pwgen -s 32 1)
        fi
        if [ -z "$DATABASE" ]
        then
            DATABASE=$(echo "${NAMESPACE}_${NAME}" | sed -e 's/-//g' | cut -c -32)
        fi

        kubectl create secret generic ${SECRET_NAME} \
            --save-config \
            --dry-run=client \
            --from-literal="user=${DATABASE}" \
            --from-literal="password=${MYSQL_PASSWORD}" \
            --from-literal="database=${DATABASE}" \
            -o yaml \
            -n ${NAMESPACE} | kubectl apply -f -
    fi

    common::log $NAMESPACE $NAME "Sync database"
    mysql -u ${MYSQL_ADMIN_USER} -p"${MYSQL_ADMIN_PASSWORD}" -h ${MYSQL_HOST} -e "
        CREATE DATABASE IF NOT EXISTS ${DATABASE};
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
        GRANT ALL PRIVILEGES ON ${DATABASE}.* TO '${MYSQL_USER}'@'%';
        FLUSH PRIVILEGES;
    "

    if ! kubectl -n $NAMESPACE get service $SERVICE_NAME &>/dev/null
    then
        common::log $NAMESPACE $NAME "Create service"
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  externalName: ${SERVICE_EXTERNAL_NAME}
  type: ExternalName
EOF
    fi

    if ! jq -er '.status.ready // null' $CURRENT_OBJECT >/dev/null
    then
        common::log $NAMESPACE $NAME "Add finalizer"
        common::add_finalizer $CURRENT_OBJECT
        common::log $NAMESPACE $NAME "Set ready status"
        common::set_status $CURRENT_OBJECT '{"status":{"ready":true, "database": "'$DATABASE'"}}'
    fi
}

common::run_hook "$@"