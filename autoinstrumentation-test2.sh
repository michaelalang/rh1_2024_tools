#!/bin/bash
source /etc/profile.d/otel-functions.sh

tracing::auto::init

function passwdsed() {
   sed ' s#^root:#otel:# ' < /etc/passwd > /tmp/passwd
   passwdsed2
}

function passwdsed2() {
   [ -f /tmp/passwd ] && tracing::run 'verify file' echo "go ahead"
}

function passwdverify() {
   passwdawk
   checkfreedom
   echo "hacked system"
}

function passwdawk() {
   awk '/^otel:/' < /tmp/passwd
}

function checkfreedom() {
   /usr/bin/curl -H 'content-type: application/json' \
     -H "traceparent: ${TRACEPARENT}" \
     -d@/forwards.json \
     -so/dev/null https://mockbin-ns1.apps.example.com/tracefwd \
     -X POST \
     -vk
}

passwdsed
passwdverify
