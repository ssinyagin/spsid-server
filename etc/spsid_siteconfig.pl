# All site-specific SPSID configuration goes here

$SPSID::Config::Backend::SQL::dbi_dsn =
    'DBI:mysql:database=spsid;host=localhost';

$SPSID::Config::Backend::SQL::dbi_user = 'spsid';
$SPSID::Config::Backend::SQL::dbi_password = 'Uwae4hei',
$SPSID::Config::Backend::SQL::dbi_attr = 
{'mysql_auto_reconnect' => 1};



1;

