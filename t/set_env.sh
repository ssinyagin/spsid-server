
if test x${SPSID_TOP} = x; then
    echo "ERROR: need to define SPSID_TOP" 1>&2
elif test ! -d ${SPSID_TOP}; then
    echo "ERROR: no such directory: ${SPSID_TOP}" 1>&2
else    
    SPSID_CONFIG=${SPSID_TOP}/share/conf_defaults/spsid_config.pl
    SPSID_SITECONFIG=${SPSID_TOP}/t/test_spsid_siteconfig.pl
    SPSID_PERLLIBDIRS=${SPSID_TOP}/lib
    export SPSID_CONFIG SPSID_SITECONFIG SPSID_PERLLIBDIRS

    SPSID_SQLITE_DB=/tmp/spsid_$$.db
    export SPSID_SQLITE_DB

    SPSID_PLACK_PIDFILE=/tmp/spsid_plack_$$.pid
    export SPSID_PLACK_PIDFILE

    SPSID_PLACK_PORT=9099
    SPSID_PLACK_HOST=127.0.0.1
    SPSID_PLACK_URL=http://${SPSID_PLACK_HOST}:${SPSID_PLACK_PORT}/
    SPSID_PLACK_LOG=/tmp/plack_acces_log_$$
    export SPSID_PLACK_PORT SPSID_PLACK_HOST SPSID_PLACK_URL SPSID_PLACK_LOG
fi








