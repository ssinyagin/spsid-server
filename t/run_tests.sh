
if test x${TOP_BUILDDIR} = x; then
    TOP_BUILDDIR=`dirname $0`/..
fi

if test x${SQLITE3} = x; then
    SQLITE3=`which sqlite3`
    if test $? -ne 0; then
        echo "Cannot find sqlite3" 1>&2
        exit 1
    fi
fi



SPSID_CONFIG=${TOP_BUILDDIR}/share/conf_defaults/spsid_config.pl
SPSID_SITECONFIG=${TOP_BUILDDIR}/t/test_spsid_siteconfig.pl
SPSID_PERLLIBDIRS=${TOP_BUILDDIR}/lib

export SPSID_CONFIG SPSID_SITECONFIG SPSID_PERLLIBDIRS

SPSID_SQLITE_DB=/tmp/spsid_$$.db

echo "Initializing SPSID database in ${SPSID_SQLITE_DB}" 1>&2

${SQLITE3} -init ${TOP_BUILDDIR}/share/sql/spsid_schema.ansi.sql \
    ${SPSID_SQLITE_DB} .quit

if test $? -ne 0; then
    echo "Failed to initialize ${SPSID_SQLITE_DB}" 1>&2
    exit 1
fi

export SPSID_SQLITE_DB

echo "Starting Plack server" 1>&2

plackup --host 127.0.0.1 --port 9099 \
    ${TOP_BUILDDIR}/share/psgi/spsid_jsonrpc.psgi &

PLACK_PID=$!

sleep 3

ps -p $PLACK_PID

echo "Checking if Plack server is reachable" 1>&2

curl http://127.0.0.1:9099/ \
    --data-binary \
    '{"jsonrpc":"2.0","method":"ping","params":["a","b"],"id":"1"}'

echo

if test $? -ne 0; then
    echo "Failed to connect to Plack server" 1>&2
    kill $PLACK_PID
    exit 1
fi




kill $PLACK_PID
rm -f ${SPSID_SQLITE_DB}




