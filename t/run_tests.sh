
. `dirname $0`/set_env.sh

if test x${SPSID_CONFIG} = x; then
    echo "ERROR: failed to initialize the environment" 1>&2
    exit 1
fi


${SHELL} ${SPSID_SRV_TOP}/t/init_db.sh

if test $? -ne 0; then
    echo "ERROR: cannot initialize the database" 1>&2
    exit 1
fi

${SHELL} ${SPSID_SRV_TOP}/t/start_plack.sh

if test $? -ne 0; then
    echo "ERROR: Failed to start Plack server" 1>&2
    exit 1
fi

${PERL} ${SPSID_CL_BIN}/spsid_siam_init --url=${SPSID_PLACK_URL}

if test $? -ne 0; then
    echo "ERROR: Failed to initialize SIAM root" 1>&2
    ${SHELL} ${SPSID_SRV_TOP}/t/stop_plack.sh
    ${SHELL} ${SPSID_SRV_TOP}/t/delete_db.sh
    exit 1
fi


DATA_YAML=${SPSID_SRV_TOP}/t/siam_test_data.yaml
echo "Loading objects from ${DATA_YAML}" 1>&2

${PERL} ${SPSID_CL_BIN}/spsid_siam_load_yaml --url=${SPSID_PLACK_URL} \
    --in=${DATA_YAML}

if test $? -ne 0; then
    echo "ERROR: Failed to load YAML data" 1>&2
    ${SHELL} ${SPSID_SRV_TOP}/t/stop_plack.sh
    ${SHELL} ${SPSID_SRV_TOP}/t/delete_db.sh
    exit 1
fi


${PERL} ${SPSID_SRV_TOP}/t/run_tap_harness.pl 


${SHELL} ${SPSID_SRV_TOP}/t/stop_plack.sh
${SHELL} ${SPSID_SRV_TOP}/t/delete_db.sh






