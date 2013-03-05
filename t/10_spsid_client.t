#!perl -T

use strict;
use warnings;

use Test::More tests => 4;

BEGIN {
    ok(defined($ENV{'SPSID_CONFIG'})) or BAIL_OUT('');
    require_ok($ENV{'SPSID_CONFIG'})  or BAIL_OUT('');
}

use SPSID::Client;

my $client = SPSID::Client->new(url => $ENV{'SPSID_PLACK_URL'});
ok($client, 'SPSID::Client->new');

my $root = $client->get_siam_root();
ok($root, '$client->get_siam_root()');

my $r = $client->search_objects($root, 'SIAM::Device',
                                'siam.device.inventory_id', 'ZUR8050AN33');
ok(scalar(@{$r} == 1), 'search device ZUR8050AN33');
my $device = $r->[0]->{'spsid.object.id'};


# try to create a duplicate root

my $id;
eval {
    $id = $client->create_object
        ('SIAM',
         {
          'spsid.object.container' => 'NIL',
          'siam.object.complete' => 1,
         })};

ok((not defined($id) and $@), 'duplicate SIAM root') or
    BAIL_OUT('Succeeded to create duplicate root objects');

# try to create a SIAM::ServiceComponent at the top level

eval {
    $id = $client->create_object
        ('SIAM::ServiceComponent',
         {
          'spsid.object.container' => $root,
          'siam.object.complete' => 1,
          'siam.svcc.name' => 'XX',
          'siam.svcc.type' => 'XX',
          'siam.svcc.inventory_id' => 'XX',
          'siam.svcc.device_id' => $device,
         })};

ok((not defined($id) and $@), 'create object with wrong container');



# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:







