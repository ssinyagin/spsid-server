
echo "Starting Plack server at ${SPSID_PLACK_URL}" 1>&2

plackup --host ${SPSID_PLACK_HOST} --port ${SPSID_PLACK_PORT} \
    --access-log ${SPSID_PLACK_LOG} \
    -e "close STDERR; open (STDERR, \">${SPSID_PLACK_ERRLOG}\")" \
    ${SPSID_TOP}/share/psgi/spsid_jsonrpc.psgi &

PLACK_PID=$!

echo ${PLACK_PID} >${SPSID_PLACK_PIDFILE}
sleep 3

ps -p ${PLACK_PID}

echo "Checking if Plack server is reachable" 1>&2

curl ${SPSID_PLACK_URL} \
    --data-binary \
    '{"jsonrpc":"2.0","method":"ping","params":{"ok":"1"},"id":"1"}'

if test $? -ne 0; then
    echo "Failed to connect to Plack server" 1>&2
    kill $PLACK_PID
    exit 1
fi

echo
echo "Plack server started" 1>&2


