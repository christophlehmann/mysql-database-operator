function common::run_hook() {
  if [[ $1 == "--config" ]] ; then
    hook::config
  else
    hook::trigger
  fi
}

function common::add_finalizer() {
    local OBJECT=$1

    local NAME=$(jq -r '.metadata.name' $OBJECT)
    local NAMESPACE=$(jq -r '.metadata.namespace' $OBJECT)
    local KIND=$(jq -r ".kind" $OBJECT)
    local FINALIZER_NAME=$(echo "${KIND}-operator" | tr '[:upper:]' '[:lower:]')

    kubectl -n $NAMESPACE patch $KIND $NAME --type merge -p '{"metadata":{"finalizers": ["'${FINALIZER_NAME}'"]}}' >/dev/null
}

function common::remove_finalizer() {
    local OBJECT=$1

    local NAME=$(jq -r '.metadata.name' $OBJECT)
    local NAMESPACE=$(jq -r '.metadata.namespace' $OBJECT)
    local KIND=$(jq -r ".kind" $OBJECT)

    kubectl -n $NAMESPACE patch $KIND $NAME --type merge -p '{"metadata":{"finalizers": null}}' >/dev/null
}

function common::has_finalizer() {
    local OBJECT=$1

    if jq -er '.metadata.finalizers // null' $OBJECT >/dev/null
    then
        return 0
    fi

    return 1
}

function common::should_be_deleted() {
    local OBJECT=$1

    if jq -er ".metadata.deletionTimestamp // null" $OBJECT >/dev/null
    then
      return 0
    fi

    return 1
}

function common::log() {
    local NAMESPACE=$1
    local NAME=$2
    local MESSAGE="$3"

    echo "${NAMESPACE}/${NAME}: $MESSAGE"
}

function common::log_error() {
    local NAMESPACE=$1
    local NAME=$2
    local MESSAGE="$3"

    echo "${NAMESPACE}/${NAME}: $MESSAGE" 1>&2
}

function common::set_status () {
    local OBJECT=$1
    local JSON_PATCH="$2"

    local SELF_LINK=$(jq -r ".metadata.selfLink" $OBJECT)

    # In Kubernetes v1.24 kubectl is able to manage the subresource "status", see https://github.com/kubernetes/kubernetes/pull/99556
    # For now the status is set with curl. The curl request works only in cluster.
    curl --fail -ks -XPATCH \
        -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
        -H "Content-Type: application/merge-patch+json" \
        -H "Accept: application/json" \
        --data "$JSON_PATCH" \
        https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}${SELF_LINK}/status >/dev/null
}