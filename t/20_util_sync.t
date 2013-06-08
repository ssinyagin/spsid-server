#!perl

## Tests for SPSID::Util->sync_contained_objects

use strict;
use warnings;

use Test::More tests => 20;

BEGIN {
    ok(defined($ENV{'SPSID_CONFIG'})) or BAIL_OUT('');
    require_ok($ENV{'SPSID_CONFIG'})  or BAIL_OUT('');
}

use SPSID::Client;
use SPSID::Util;

my $client = SPSID::Client->new(url => $ENV{'SPSID_PLACK_URL'});
ok($client, 'SPSID::Client->new');

my $util = SPSID::Util->new(client => $client);
ok($util, 'SPSID::Util->new');

my $root = $client->get_siam_root();
ok($root, '$client->get_siam_root()');

my $devices = [
           {
            'siam.device.inventory_id' => 'DEV01',
            'siam.device.name' => 'DEV01',
            'siam.object.complete' => '1',
            'snmp.managed' => '1',
            'snmp.host' => 'DEV01.domain.net',
           },
           {
            'siam.device.inventory_id' => 'DEV02',
            'siam.device.name' => 'DEV02',
            'siam.object.complete' => '1',
           },
              ];

$util->sync_contained_objects($root, 'SIAM::Device', $devices);

{
    my $r = $client->search_objects($root, 'SIAM::Device');
    ok(scalar(@{$r} == 2), 'search devices after sync_contained_objects');
    
    my $dev01;
    my $dev02;
    
    foreach my $obj (@{$r}) {
        if( $obj->{'siam.device.inventory_id'} eq 'DEV01' ) {
            $dev01 = $obj;
        }
        elsif( $obj->{'siam.device.inventory_id'} eq 'DEV02' ) {
            $dev02 = $obj;
        }
    }
    ok((defined($dev01) and defined($dev02)),
       'DEV01 and DEV02 are found in DB');

    ok((scalar(keys %{$dev01}) == 8 and scalar(keys %{$dev02}) == 6),
       'DEV01 has 8 attributes and DEV02 has 6');
}

# add, modify and delete attributes
delete $devices->[0]->{'snmp.managed'};
$devices->[0]->{'snmp.host'} = 'foobar';
$devices->[0]->{'foo'} = 'bar';
$devices->[1]->{'snmp.host'} = 'dung';
$devices->[1]->{'siam.object.complete'} = '0';

$util->sync_contained_objects($root, 'SIAM::Device', $devices);

{
    my $r = $client->search_objects($root, 'SIAM::Device');
    ok(scalar(@{$r} == 2), 'search devices after sync_contained_objects');
    
    my $dev01;
    my $dev02;

    foreach my $obj (@{$r}) {
        if( $obj->{'siam.device.inventory_id'} eq 'DEV01' ) {
            $dev01 = $obj;
        }
        elsif( $obj->{'siam.device.inventory_id'} eq 'DEV02' ) {
            $dev02 = $obj;
        }
    }

    ok((defined($dev01) and defined($dev02)),
       'DEV01 and DEV02 are again found in DB');

    ok((not defined($dev01->{'snmp.managed'})),
       'not defined $dev01->{\'snmp.managed\'}');
    
    ok((defined($dev01->{'snmp.host'}) and $dev01->{'snmp.host'} eq 'foobar'),
       '$dev01->{\'snmp.host\'} defined and set to foobar');
    
    ok((defined($dev01->{'foo'}) and $dev01->{'foo'} eq 'bar'),
       '$dev01->{\'foo\'} defined and set to bar');
    
    ok((defined($dev02->{'snmp.host'}) and $dev02->{'snmp.host'} eq 'dung'),
       '$dev02->{\'snmp.host\'} defined and set to dung');
    
    ok((not $dev02->{'siam.object.complete'}),
       'not $dev02->{\'siam.object.complete\'}');    
}


push(@{$devices},
 {
  'siam.device.inventory_id' => 'DEV02',
  'siam.device.name' => 'DEV02',
  'siam.object.complete' => '1',
 });


eval {
    $util->sync_contained_objects($root, 'SIAM::Device', $devices);
};

ok($@, 'duplicate sync objects generate exception');

{
    my $r = $client->search_objects($root, 'SIAM::Device');
    ok(scalar(@{$r} == 2), 'search devices after exception returns 2 objects');
}

$devices->[2] =
{
 'siam.device.inventory_id' => 'DEV03',
 'siam.device.name' => 'DEV03',
 'siam.object.complete' => '1',
};

$util->sync_contained_objects($root, 'SIAM::Device', $devices);

{
    my $r = $client->search_objects($root, 'SIAM::Device');
    ok(scalar(@{$r} == 3), 'added an object');
}

shift @{$devices};

$util->sync_contained_objects($root, 'SIAM::Device', $devices);

{
    my $r = $client->search_objects($root, 'SIAM::Device');
    ok(scalar(@{$r} == 2), 'deleted an object');

    my $dev02;
    my $dev03;
    
    foreach my $obj (@{$r}) {
        if( $obj->{'siam.device.inventory_id'} eq 'DEV02' ) {
            $dev02 = $obj;
        }
        elsif( $obj->{'siam.device.inventory_id'} eq 'DEV03' ) {
            $dev03 = $obj;
        }
    }
    ok((defined($dev02) and defined($dev03)),
       'DEV02 and DEV03 are found in DB');    
}












# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
