export OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4317}

function traceparent() {
  local tid="$(<<<${TRACEPARENT:-} cut -d- -f2)"
  tid="${tid:-"$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)"}"
  local sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"
  TRACEPARENT="00-${tid}-${sid}-01" "${@:2}"
}

function startspan() {
  traceparent
  sockdir=$(mktemp -d)
  otel-cli span background \
   --service ${OTEL_SPAN_SERVICE:-curl} \
   --name "${OTEL_SPAN_NAME:-curl}" \
   --protocol grpc \
   --attrs="os.hostname=${HOSTNAME},os.pwd=$(pwd),os.uid=$(id -u),os.group=$(id -g)" \
   --timeout 300 \
   --sockdir $sockdir & >/dev/null 2>&1 
  sleep .1
}

function tracecmd() {
  traceparent
  start=$(date --iso-8601=ns)
  ocmd=$@
  "$@"
  status=$?
  if [ "${status}" == "0" ] ; then 
     status='ok'
  else
     status='error'
  fi
  ocmd=$(jq -c -n '$ARGS.positional' --args "${ocmd[@]}" | sed -s 's#"##g; s#\[##; s#\]##;')
  echo "Status=${status}"
  end=$(date --iso-8601=ns)
  otel-cli span \
    --verbose \
    --protocol grpc \
    --attrs="os.hostname=${HOSTNAME},os.pwd=$(pwd),os.uid=$(id -u),os.group=$(id -g),os.cmd=${ocmd}" \
    --service "${OTEL_SPAN_SERVICE:-$0}" \
    --name "${OTEL_SPAN_NAME:-${ocmd[0]}}" \
    --status-code=${status} \
    --start $start \
    --end $end
} 

function stopspan() {
  otel-cli span end --sockdir $sockdir
}

function tracespan() {
  traceparent
  otel-cli span event \
    --name "$@" \
    --attrs "cmd=$@" \
    --sockdir $sockdir
  "$@"
}

function ocurl() {
  otel-cli exec --protocol grpc \
    --attrs="os.hostname=${HOSTNAME},os.pwd=$(pwd),os.uid=$(id -u),os.group=$(id -g)" \
    --service ${OTEL_SERVICE:-curl} \
    --name "${OTEL_NAME:-curl}" -- \
    /usr/bin/curl -H 'traceparent: {{traceparent}}' "$@"
}

function curl() {
  traceparent
  echo ${TRACEPARENT}
  /usr/bin/curl -H "traceparent: ${TRACEPARENT}" "$@" 
}

# Usage: tracing::init [endpoint; default localhost:4317]
function tracing::init() {
  export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-https://tempo-grpc.example.com:443}"
}

# Usage: tracing::auto::init [endpoint; default localhost:4317]
function tracing::auto::init() {
  tracing::init
  set -o functrace

  # First, get a trace and span ID. We need to get one now so we can propogate it to the child
  # Get trace ID from TRACEPARENT, if present
  trace="$(<<<${TRACEPARENT:-} cut -d- -f2)"
  trace="${trace:-"$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)"}"
  echo "Trace ${trace}"
  spans=()
  starts=()
  oldparents=()
  function tracing::internal::on_debug() {
      # We will get a callback for each operation in the function. We just want it for the function initially entering
      # This is probably not handling recursive calls correctly.
      [[ "${FUNCNAME[1]}" != "$(<<<$BASH_COMMAND cut -d' ' -f1)" ]] && return
      local tp=`tr -dc 'a-f0-9' < /dev/urandom | head -c 16`
      spans+=("$tp")
      starts+=("$(date -u +%s.%N)")
      oldparents+=("${TRACEPARENT:-}")
      TRACEPARENT="00-${trace}-${tp}-01"
  }
  function tracing::internal::on_return() {
      if [[ ${#spans[@]} == 0 ]]; then
        # This happens on the call to tracing::init
        return
      fi
      local tp=""
      if [[ ${#spans[@]} -gt 1 ]]; then
        tp="00-${trace}-${spans[-2]}-01"
      fi
      local span="${spans[-1]}"
      local start="${starts[-1]}"
      local nextparent="${oldparents[-1]}"
      unset spans[-1]
      unset starts[-1]
      unset oldparents[-1]

      TRACEPARENT=$nextparent otel-cli span \
        --protocol grpc \
        --service "${BASH_SOURCE[-1]}" \
        --name "${FUNCNAME[1]}" \
        --attrs="os.hostname=${HOSTNAME},os.pwd=$(pwd),os.uid=$(id -u),os.group=$(id -g)"  \
        --start "$start" \
        --end "$(date -u +%s.%N)" \
        --force-trace-id "$trace" \
        --force-span-id "$span"
      TRACEPARENT="${nextparent}"
  }

  trap tracing::internal::on_return RETURN
  trap tracing::internal::on_debug DEBUG
}

# Usage: tracing::run <span name> [command ...]
function tracing::run() {
  # Throughout, "local" usage is critical to avoid nested calls overwriting things
  local start="$(date -u +%s.%N)"
  # First, get a trace and span ID. We need to get one now so we can propagate it to the child
  # Get trace ID from TRACEPARENT, if present
  local tid="$(<<<${TRACEPARENT:-} cut -d- -f2)"
  tid="${tid:-"$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)"}"
  # Always generate a new span ID
  local sid="$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)"

  # Execute the command they wanted with the propagation through TRACEPARENT
  TRACEPARENT="00-${tid}-${sid}-01" "${@:2}"

  local end="$(date -u +%s.%N)"

  # Now report this span. We override the IDs to the ones we set before.
  # TODO: support attributes
  otel-cli span \
    --protocol grpc \
    --service "${BASH_SOURCE[-1]}" \
    --name "$1" \
    --attrs="os.hostname=${HOSTNAME},os.pwd=$(pwd),os.uid=$(id -u),os.group=$(id -g)"  \
    --status-code=${SPAN_STATUS:-"ok"} \
    --start "$start" \
    --end "$end" \
    --force-trace-id "$tid" \
    --force-span-id "$sid"
}

# Usage: tracing::decorate <function>
# Automatically makes a function traced.
function tracing::decorate() {
eval "\
function $1() {
_$(typeset -f "$1")
tracing::run '$1' _$1
}
"
}

function strace() {
  traceparent 
  /usr/bin/strace -ttt "$@" 2>&1 >/dev/null | /usr/local/bin/.strace
}
