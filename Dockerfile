FROM flant/shell-operator:v1.0.10

RUN apk add --no-cache pwgen mysql-client mariadb-connector-c curl

ADD hooks /hooks
