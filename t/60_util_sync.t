#!perl

## Tests for SPSID::Util->sync_contained_objects

use strict;
use warnings;

use Test::More tests => 31;

BEGIN {
    ok(defined($ENV{'SPSID_PLACK_URL'})) or BAIL_OUT('');
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

    $client->modify_object($dev01->{'spsid.object.id'},
                           {'torrus.imported' => 1});
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

    ok((defined($dev01->{'torrus.imported'}) and
        $dev01->{'torrus.imported'}==1),
       '$dev01->{\'torrus.imported\'} defined and set to 1');
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

# test default_autogen attributes
{
    my $r = $client->search_objects($root, 'SIAM::Device',
                                    'siam.device.inventory_id', 'DEV02');

    ok(scalar(@{$r} == 1), 'selected DEV02');
    my $device = $r->[0]->{'spsid.object.id'};

    my $ports =
        [
         {
          'siam.devc.type' => 'IFMIB.Port',
          'siam.devc.name' => 'GigabitEthernet0/1',
          'siam.devc.description' => 'SAP200001',
          'torrus.nodeid' => 'xxx1',
          'torrus.imported' => 1,
          'siam.object.complete' => 1,
         },
         {
          'siam.devc.type' => 'IFMIB.Port',
          'siam.devc.name' => 'GigabitEthernet0/2',
          'siam.devc.description' => 'SAP200001',
          'torrus.nodeid' => 'xxx2',
          'torrus.imported' => 1,
          'siam.object.complete' => 1,
         },
        ];

    $util->sync_contained_objects($device, 'SIAM::DeviceComponent', $ports);
    
    $r = $client->search_objects($device, 'SIAM::DeviceComponent',
                                 'siam.devc.name', 'GigabitEthernet0/2');
    ok(scalar(@{$r} == 1), 'selected GigabitEthernet0/2');
    my $p = $r->[0];

    ok(($p->{'torrus.nodeid'} ne 'xxx2'), 'torrus.nodeid ne xxx2');
    ok((not defined $p->{'torrus.imported'}), 'not defined torrus.imported');
    ok(($p->{'siam.devc.inventory_id'} =~ /^SPSID\d+$/),
       'siam.devc.inventory_id is auto-generated');
    
    # modify the auto-generated value
    $ports->[1]->{'siam.devc.inventory_id'} = 'XXXX111';
    $util->sync_contained_objects($device, 'SIAM::DeviceComponent', $ports);
    
    $r = $client->search_objects($device, 'SIAM::DeviceComponent',
                                 'siam.devc.name', 'GigabitEthernet0/2');
    ok(scalar(@{$r} == 1), 'selected GigabitEthernet0/2');
    $p = $r->[0];

    ok(($p->{'siam.devc.inventory_id'} eq 'XXXX111'),
       'siam.devc.inventory_id is modified');

    # auto-generated attribut is not deleted and keeps its value
    delete $ports->[1]->{'siam.devc.inventory_id'};
    $util->sync_contained_objects($device, 'SIAM::DeviceComponent', $ports);

    $r = $client->search_objects($device, 'SIAM::DeviceComponent',
                                 'siam.devc.name', 'GigabitEthernet0/2');
    ok(scalar(@{$r} == 1), 'selected GigabitEthernet0/2');
    $p = $r->[0];

    ok(($p->{'siam.devc.inventory_id'} eq 'XXXX111'),
       'siam.devc.inventory_id staus untouched');

    # test unique_child uniqueness
    
    my $new_port = {
                    'siam.devc.type' => 'IFMIB.Port',
                    'siam.devc.name' => 'GigabitEthernet0/2',
                    'siam.devc.description' => 'SAP200001',
                    'torrus.nodeid' => 'xxx2',
                    'torrus.imported' => 1,
                    'siam.object.complete' => 1,
                   };
    
    push(@{$ports}, $new_port);
    eval {
        $util->sync_contained_objects($device, 'SIAM::DeviceComponent', $ports);
    };
    ok($@, 'unique_child uniqueness in sync_contained_objects');

    $new_port = $client->new_object_default_attrs
        ($device, 'SIAM::DeviceComponent', $new_port);

    eval {
        $client->create_object('SIAM::DeviceComponent', $new_port);
    };
    ok($@, 'unique_child uniqueness in create_object');
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
