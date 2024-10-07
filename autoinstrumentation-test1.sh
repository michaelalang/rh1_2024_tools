#!/bin/bash
source /tmp/otel-trace.sh

tracing::auto::init

function passwdsed() {
   tracing::run 'sed passwd' sed ' s#^root:#otel:# ' < /etc/passwd > /tmp/passwd
   passwdverify
}

function passwdverify() {
   passwdawk
   checkfreedom
   echo "hacked system"
}

function passwdawk() {
   tracing::run 'awk passwd' awk '/^otel:/' < /tmp/passwd
}

function checkfreedom() {
   tracing::run 'curl for google' /usr/bin/curl -so/dev/null https://www.google.com
}

passwdsed

