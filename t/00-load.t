#!perl -T

use Test::More tests => 4;

BEGIN {
    use_ok('SPSID::Server') or BAIL_OUT('');
    use_ok('SPSID::Server::Backend::SQL') or BAIL_OUT('');
    use_ok('SPSID::Client') or BAIL_OUT('');
    use_ok('SPSID::Util') or BAIL_OUT('');
}


