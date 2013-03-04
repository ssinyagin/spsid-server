
if test x${SQLITE3} = x; then
    SQLITE3=`which sqlite3`
    if test $? -ne 0; then
        echo "Cannot find sqlite3" 1>&2
        exit 1
    fi
fi

echo "Initializing SPSID database in ${SPSID_SQLITE_DB}" 1>&2

${SQLITE3} -init ${TOP_BUILDDIR}/share/sql/spsid_schema.ansi.sql \
    ${SPSID_SQLITE_DB} .quit

if test $? -ne 0; then
    echo "Failed to initialize ${SPSID_SQLITE_DB}" 1>&2
    exit 1
fi





