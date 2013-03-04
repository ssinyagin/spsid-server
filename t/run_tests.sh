
. `dirname $0`/set_env.sh

if test x${SPSID_CONFIG} = x; then
    echo "ERROR: failed to initialize the environment" 1>&2
    exit 1
fi


${SHELL} ${SPSID_TOP}/t/init_db.sh

if test $? -ne 0; then
    echo "ERROR: cannot initialize the database" 1>&2
    exit 1
fi

${SHELL} ${SPSID_TOP}/t/start_plack.sh

if test $? -ne 0; then
    echo "ERROR: Failed to start Plack server" 1>&2
    exit 1
fi


echo "Press ENTER"
read text


${SHELL} ${SPSID_TOP}/t/stop_plack.sh
${SHELL} ${SPSID_TOP}/t/delete_db.sh






