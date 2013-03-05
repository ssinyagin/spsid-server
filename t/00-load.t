#!perl -T

use Test::More tests => 3;

BEGIN {
    use_ok('SPSID') or BAIL_OUT('');
    use_ok('SPSID::Backend::SQL') or BAIL_OUT('');
    use_ok('SPSID::Client') or BAIL_OUT('');
}


