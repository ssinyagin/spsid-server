
if test x${SQLITE3} = x; then
    SQLITE3=`which sqlite3`
    if test $? -ne 0; then
        echo "Cannot find sqlite3" 1>&2
        exit 1
    fi
fi

SQLFILE=${SPSID_TOP}/share/sql/spsid_schema.ansi.sql

if test ! -f ${SQLFILE}; then
    echo "No such file: ${SQLFILE}" 1>&2
    exit 1
fi


echo "Initializing SPSID database in ${SPSID_SQLITE_DB}" 1>&2

${SQLITE3} -init ${SPSID_TOP}/share/sql/spsid_schema.ansi.sql \
    ${SPSID_SQLITE_DB} .quit

if test ! -f ${SPSID_SQLITE_DB} -o ! -s ${SPSID_SQLITE_DB}; then
    echo "Failed to initialize ${SPSID_SQLITE_DB}" 1>&2
    exit 1
fi





