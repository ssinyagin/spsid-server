
SPSID_ENV_OK=yes

spsid_check_dir_env () {
    arg_check_var=$1
    eval 'arg_check_dir=${'${arg_check_var}'}'
    
    if test x${arg_check_dir} = x; then
        echo "ERROR: need to define ${arg_check_var}" 1>&2
        SPSID_ENV_OK=no
    elif test ! -d ${arg_check_dir}; then
        echo "ERROR: no such directory: ${arg_check_dir}" 1>&2
        SPSID_ENV_OK=no
    fi
}


spsid_check_dir_env SPSID_SRV_TOP
spsid_check_dir_env SPSID_CL_BIN
spsid_check_dir_env SPSID_CL_LIB

if test ${SPSID_ENV_OK} = yes; then
    SPSID_CONFIG=${SPSID_SRV_TOP}/share/conf_defaults/spsid_config.pl
    SPSID_SITECONFIG=${SPSID_SRV_TOP}/t/test_spsid_siteconfig.pl
    SPSID_PERLLIBDIRS=${SPSID_SRV_TOP}/lib,${SPSID_CL_LIB}
    export SPSID_CONFIG SPSID_SITECONFIG SPSID_PERLLIBDIRS

    SPSID_SQLITE_DB=/tmp/spsid_$$.db
    export SPSID_SQLITE_DB

    SPSID_PLACK_PIDFILE=/tmp/spsid_plack_$$.pid
    export SPSID_PLACK_PIDFILE

    SPSID_PLACK_PORT=9099
    SPSID_PLACK_HOST=127.0.0.1
    SPSID_PLACK_URL=http://${SPSID_PLACK_HOST}:${SPSID_PLACK_PORT}/
    SPSID_PLACK_LOG=/tmp/plack_acces_log_$$
    SPSID_PLACK_ERRLOG=/tmp/plack_error_log_$$
    export SPSID_PLACK_PORT SPSID_PLACK_HOST SPSID_PLACK_URL
    export SPSID_PLACK_LOG SPSID_PLACK_ERRLOG
fi








