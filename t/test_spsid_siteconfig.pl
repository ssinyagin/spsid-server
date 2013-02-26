# All site-specific SPSID configuration goes here

$SPSID::Config::Backend::SQL::dbi_dsn =
    'dbi:SQLite:dbname=' . $ENV{SPSID_SQLITE_DB};

$SPSID::Config::Backend::SQL::dbi_user = '';
$SPSID::Config::Backend::SQL::dbi_password = '',



1;

