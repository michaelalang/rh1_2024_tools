FROM registry.redhat.io/ubi9/ubi

COPY requirements.txt /tmp/.requirements.txt 

RUN dnf install -y python-pip jq strace https://github.com/equinix-labs/otel-cli/releases/download/v0.4.5/otel-cli_0.4.5_linux_amd64.rpm ; \
    pip install -r /tmp/.requirements.txt

COPY otel-functions.sh /etc/profile.d/otel-functions.sh
COPY strace /usr/local/bin/.strace
COPY curl /usr/local/bin/curl
COPY strace-curl /usr/local/bin/strace-curl
COPY autoinstrumentation-test1.sh /usr/local/bin/autoinstrumentation-test1.sh
COPY autoinstrumentation-test2.sh /usr/local/bin/autoinstrumentation-test2.sh

USER 65535

ENTRYPOINT [ "/bin/bash", "--init-file", "/etc/profile.d/otel-functions.sh" ]
