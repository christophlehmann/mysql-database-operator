# A Kubernetes Operator for MySQL Databases

The operator cares about creating MySQL databases. Based on a custom resource it creates

* A MySQL database. It's name is prefixed with the namespace `namespace_databasename` and cropped to 32 characters.
* A MySQL user with all privileges for the database. Its the database name suffixed with a random string and cropped to 32 characters. 
* A secret that contains the final database name, username and password.
* A service where the database is reachable.

It's based on [flant/shell-operator](https://github.com/flant/shell-operator).

## Usage

Create a custom resource

```yaml
apiVersion: "k8s.networkteam.com/v1"
kind: MySQL57Database
metadata:
  name: myapp
spec:
  serviceName: myapp-database-service
  secretName: myapp-database-credentials
```

The operator then create this manifests

```yaml
kind: Service
apiVersion: v1
metadata:
  name: myapp-database-service
spec:
  type: ExternalName
  externalName: ${SERVICE_EXTERNAL_NAME}
---
apiVersion: v1
kind: Secret
metadata:
  name: myapp-database-credentials
type: Opaque
data:
  database:  # ... the final database name
  user:      # ... the final username
  password:  # ... the final password
```

## Deployment

```shell
# The operator namespace
export KUBE_NAMESPACE=mysql57-database-operator
# The docker image
export IMAGE=the-operator-image
export IMAGE_TAG=latest
# The service is used for creating database and user
export ADMIN_SERVICE_NAME=mysql57.mysql.svc.cluster.local
# The secret contains credentials used to create database and user 
export ADMIN_SECRET_NAME=mysql57-root-credentials
# This is the externalName, see resulting Service manifest above.
export SERVICE_EXTERNAL_NAME=mysql57.mysql.svc.cluster.local

kubectl create ns ${KUBE_NAMESPACE}
envsubst < ./ci/deploy/crd.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f - 
envsubst < ./ci/deploy/rbac.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f - 
envsubst < ./ci/deploy/deployment.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f - 
envsubst < ./ci/deploy/example/cr-mysqldatabase.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f - 
```

## Garbage collection

The operator uses a finalizer for proper garbage collection.

## Removal of custom resources

If you want to delete the custom resource, but want to keep everything else, then execute the following steps:

1. Remove the finalizer
2. Delete the custom resource