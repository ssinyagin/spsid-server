#!perl

## Tests for SPSID::Client

use strict;
use warnings;
use utf8;
use Unicode::Normalize;

use Test::More tests => 52;

BEGIN {
    ok(defined($ENV{'SPSID_CONFIG'})) or BAIL_OUT('');
    require_ok($ENV{'SPSID_CONFIG'})  or BAIL_OUT('');
}

use SPSID::Client;

my $client = SPSID::Client->new(url => $ENV{'SPSID_PLACK_URL'});
ok($client, 'SPSID::Client->new');

eval {$client->ping()};
ok((not $@), 'ping()') or
    BAIL_OUT('Could not ping: ' . $@);


my $root = $client->get_siam_root();
ok($root, '$client->get_siam_root()');

my $r = $client->search_objects($root, 'SIAM::Device',
                                'siam.device.inventory_id', 'ZUR8050AN33');
ok(scalar(@{$r} == 1), 'search device ZUR8050AN33');
my $device = $r->[0]->{'spsid.object.id'};


# try to create a duplicate root

my $id;
$id = undef;
eval {
    $id = $client->create_object
        ('SIAM',
         {
          'spsid.object.container' => 'NIL',
          'siam.object.complete' => 1,
         })};

ok((not defined($id) and $@), 'duplicate SIAM root') or
    BAIL_OUT('Succeeded to create duplicate root objects');

# Searches that should return empty lists
$r = $client->search_objects(undef, 'SIAM::Service',
                             'siam.svcunit.inventory_id', 'BIS.89999.56');
ok(scalar(@{$r} == 0), 'search nonexistent object N1');

$r = $client->search_objects(undef, 'SIAM::Service',
                             'siam.svc.inventory_id', 'BIS');
ok(scalar(@{$r} == 0), 'search nonexistent object N2');

$r = $client->search_objects($root, 'SIAM::Service',
                             'siam.svc.inventory_id', 'BIS0001');
ok(scalar(@{$r} == 0), 'search nonexistent object N3');


# Find a Service by exact match and by prefix and compare

my $r1 = $client->search_objects(undef, 'SIAM::Service',
                                 'siam.svc.inventory_id', 'BIS0002');
ok(scalar(@{$r1} == 1), 'search Service BIS0002');

my $svc = $r1->[0]->{'spsid.object.id'};

my $r2 = $client->search_prefix('SIAM::Service',
                                'xyz.svc.street', 'datas');
ok(scalar(@{$r2} == 2), 'prefix search Service by street');


ok((($svc eq $r2->[0]->{'spsid.object.id'}) or
    ($svc eq $r2->[1]->{'spsid.object.id'})),
   'prefix search and exact search return the same object');


# search by Unicode prefix
my $r3 = $client->search_prefix('SIAM::Service',
                                'xyz.svc.city', 'düben');
ok(scalar(@{$r3} == 2), 'Unicode prefix search Service by city');

ok((($svc eq $r3->[0]->{'spsid.object.id'}) or
    ($svc eq $r3->[1]->{'spsid.object.id'})),
   'Unicode prefix search returns the same object');

# exact Unicode search
my $r4 = $client->search_objects(undef, 'SIAM::Service',
                                 'xyz.svc.city', 'Dübendorf');
ok(scalar(@{$r4} == 2), 'Unicode exact search Service by city');

ok((($svc eq $r4->[0]->{'spsid.object.id'}) or
    ($svc eq $r4->[1]->{'spsid.object.id'})),
   'Unicode prefix search returns the same object');

# search by prefix with removed umlaut
my $r5 = $client->search_prefix('SIAM::Service',
                                'xyz.svc.city', 'duben');
ok(scalar(@{$r5} == 2), 'ASCII-zed prefix search Service by city');

ok((($svc eq $r5->[0]->{'spsid.object.id'}) or
    ($svc eq $r5->[1]->{'spsid.object.id'})),
   'ASCII-zed prefix search returns the same object');


# search any attribute by prefix
my $r6 = $client->search_prefix('SIAM::Service', undef, 'datastr');
ok(scalar(@{$r6} == 2), 'Prefix search Service by any attribute');

ok((($svc eq $r6->[0]->{'spsid.object.id'}) or
    ($svc eq $r6->[1]->{'spsid.object.id'})),
   'Any-attribute prefix search returns the same object');


$r = $client->search_objects(undef, 'SIAM::ServiceComponent',
                             'siam.svcc.inventory_id', 'SRVC0001.01.u02.c01');
ok((scalar(@{$r} == 1) and defined($r->[0]->{'siam.svcc.device_id'})),
   'find the ServiceComponent');

# test calculated attribute
ok(($r->[0]->{'torrus.port.nodeid'} eq 'spsid-port//SRVC0001.01.u02.c01'),
   "calculated attribute has the expected value") or
    diag("calculated attr torrus.port.nodeid has unexpected value: " .
         $r->[0]->{'torrus.port.nodeid'});

# modify the object and see the calculated attribute
$id = $r->[0]->{'spsid.object.id'};
$client->modify_object
    ($id, {'siam.svcc.inventory_id' => 'SRVC0001.01.u02.c99'});
$r = $client->get_object($id);

ok(($r->{'torrus.port.nodeid'} eq 'spsid-port//SRVC0001.01.u02.c99'),
   "[modified] calculated attribute has the expected value") or
    diag("[modified] calculated attr " .
         "torrus.port.nodeid has unexpected value: " .
         $r->{'torrus.port.nodeid'});


# test validate_object()
my $oldref = $r->{'siam.svcc.device_id'};
$r->{'siam.svcc.device_id'} = "xxxx";
my $result = $client->validate_object($r);
ok((not $result->{'status'}), "validate_object() returns a failure");
ok((defined($result->{'error'})), "validate_object() returns an error message");
# diag($result->{'error'});
$r->{'siam.svcc.device_id'} = $oldref;
$result = $client->validate_object($r);
ok($result->{'status'}, "validate_object() returns success");


# test new_object_default_attrs()
my $container = $r->{'spsid.object.container'};
$r = $client->new_object_default_attrs
    ($container,  'SIAM::ServiceComponent',
     {'siam.svcc.type' => 'IFMIB.Port'});
# the attributes are autogenerated as UUID
ok(($r->{'siam.svcc.inventory_id'} =~ /^[0-9A-F-]+$/),
   "new_object_default_attrs() sets siam.svcc.inventory_id to UUID");
ok(($r->{'siam.svcc.name'} =~ /^[0-9A-F-]+$/),
   "new_object_default_attrs() sets siam.svcc.name to UUID");


# Check unicode attribute

my $x = $r1->[0]->{'xyz.svc.city'};
ok(utf8::is_utf8($x),
   'xyz.svc.city is a valid Unicode string');

my $y = 'Dübendorf';
utf8::decode($y);

ok(($x eq $y),
   'Unicode string in attribute value');


# try to create a SIAM::ServiceComponent at the top level
$id = undef;
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


# try to create a SIAM::ServiceUnit with duplicate inventory ID
$id = undef;
eval {
    $id = $client->create_object
        ('SIAM::ServiceUnit',
         {
          'spsid.object.container' => $svc,
          'siam.object.complete' => 1,
          'siam.svcunit.name' => 'xxx',
          'siam.svcunit.type' => 'xxx',
          'siam.svcunit.inventory_id' => 'BIS.64876.45',
         })};

ok((not defined($id) and $@), 'create ServiceUnit with duplicate inventory_id');

# Create, modify, delete SIAM::ServiceUnit

$id = undef;
eval {
    $id = $client->create_object
        ('SIAM::ServiceUnit',
         {
          'spsid.object.container' => $svc,
          'siam.object.complete' => 1,
          'siam.svcunit.name' => 'xxx',
          'siam.svcunit.type' => 'xxx',
          'siam.svcunit.inventory_id' => 'xxxx',
          'xyz.xyz.xxx' => 'xxxx',
         })};

ok((defined($id) and not $@), 'create a new ServiceUnit');

$r = $client->get_object($id);
ok(($r->{'xyz.xyz.xxx'} eq 'xxxx'), 'custom attribute in created object');

$client->modify_object
    ($id,
     {
      'siam.svcunit.name' => 'yyyy',
      'xyz.xyz.xyz' => 'xxxx',
      'xyz.xyz.xxx' => undef,
     });

$r = $client->get_object($id);

ok(($r->{'siam.svcunit.name'} eq 'yyyy'), 'attribute value modification');
ok(($r->{'xyz.xyz.xyz'} eq 'xxxx'), 'adding an attribute');
ok((not defined($r->{'xyz.xyz.xxx'})), 'deleting an attribute');


$r = $client->contained_classes($id);
ok((scalar(@{$r}) == 0), 'contained_classes N1');

$r = $client->contained_classes($svc);
ok(((scalar(@{$r}) == 1) and ($r->[0] eq 'SIAM::ServiceUnit')),
   'contained_classes N2');

my $log = $client->get_object_log($id);
ok((scalar(@{$log}) == 4), 'get_object_log') or
    diag('get_object_log returned ' . scalar(@{$log}) . ' iems');


# create a ServiceComponent with missing a mandatory template member
my $svcc = undef;
eval {
    $svcc = $client->create_object
        ('SIAM::ServiceComponent',
         {
          'spsid.object.container' => $id,
          'siam.object.complete' => 1,
          'siam.svcc.name' => 'XX',
          'siam.svcc.type' => 'IFMIB.Port',
          'siam.svcc.inventory_id' => 'XX1',
          'siam.svcc.device_id' => $device,
         })};

ok((not defined($svcc) and $@),
   'create an object with missing mandatory template member');
# diag($@);

# create an object with wrong dictionary attribute
$svcc = undef;
eval {
    $svcc = $client->create_object
        ('SIAM::ServiceComponent',
         {
          'spsid.object.container' => $id,
          'siam.object.complete' => 1,
          'siam.svcc.name' => 'XX',
          'siam.svcc.type' => 'Foobar',
          'siam.svcc.inventory_id' => 'XX1',
          'siam.svcc.device_id' => $device,
         })};

ok((not defined($svcc) and $@),
   'create an object with wrong dictionary attribute');

# create an object with wrong template member
$svcc = undef;
eval {
    $svcc = $client->create_object
        ('SIAM::ServiceComponent',
         {
          'spsid.object.container' => $id,
          'siam.object.complete' => 1,
          'siam.svcc.name' => 'XX',
          'siam.svcc.type' => 'HOST.Virtual',
          'torrus.port.name' => 'GigabitEthernet1/0/1',
          'siam.svcc.inventory_id' => 'XX1',
          'siam.svcc.device_id' => $device,
         })};

ok((not defined($svcc) and $@),
   'create an object with wrong template member');
# diag($@);



$client->delete_object($id);
$r = undef;
eval { $r = $client->get_object($id); };
ok((not defined($r) and $@), 'fetch a deleted object');


# delete a device and check that the referring ServiceComponent got NIL
# in the reference
$client->delete_object($device);
$r = $client->search_objects(undef, 'SIAM::ServiceComponent',
                             'siam.svcc.inventory_id', 'SRVC0001.01.u01.c01');
ok((scalar(@{$r}) == 1), 'retrieve ServiceComponent SRVC0001.01.u01.c01');
ok(($r->[0]->{'siam.svcc.device_id'} eq 'NIL'),
   'siam.svcc.device_id set to NIL after device is deleted');


# delete a contract and check that contained objects are deleted and
# the ScopeMember got NIL in the reference

$r = $client->search_objects(undef, 'SIAM::Contract',
                             'siam.contract.inventory_id', 'INVC0001');
ok((scalar(@{$r}) == 1), 'retrieve Contract INVC0001');
my $contract = $r->[0]->{'spsid.object.id'};

$client->delete_object($contract);
$r = $client->search_objects(undef, 'SIAM::ServiceComponent',
                             'siam.svcc.inventory_id', 'SRVC0001.01.u01.c01');
ok((scalar(@{$r}) == 0),
   'ServiceComponent objects are deleted after contract deletion');

$r = $client->search_objects(undef, 'SIAM::AccessScope',
                             'siam.scope.name', 'Contract.0001');
ok((scalar(@{$r}) == 1), 'retrieve AccessScope Contract.0001');
my $scope = $r->[0]->{'spsid.object.id'};

$r = $client->search_objects($scope, 'SIAM::ScopeMember');
ok((scalar(@{$r}) == 1), 'retrieve scope members of Contract.0001');
ok(($r->[0]->{'siam.scmember.object_id'} eq 'NIL'),
   'siam.scmember.object_id set to NUL after contract deletion');








# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
