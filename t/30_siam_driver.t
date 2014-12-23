#!perl

## Tests for SIAM::Driver::SPSID

use strict;
use warnings;

use YAML ();
use JSON;

use Test::More;

BEGIN {
    eval {require SIAM};
    if( $@ )
    {
        plan skip_all => 'SIAM is not present';
    }
    else
    {
        plan tests => 35;
    }    
}


ok(defined($ENV{'SPSID_PLACK_URL'})) or BAIL_OUT('');



my $yaml = <<EOT;
---
Driver:
  Class: SIAM::Driver::SPSID
  Options:
    SPSID_URL: %s
    SPSID_REALM: x
    SPSID_USER: x
    SPSID_PW: x
EOT

my $config = YAML::Load(sprintf($yaml, $ENV{'SPSID_PLACK_URL'}));
ok(ref($config)) or diag('Failed to read the configuration YAML');

note('loading SIAM');
ok( defined(my $siam = new SIAM($config)), 'load SIAM');

note('connecting the driver');
ok($siam->connect(), 'connect');


my $component = $siam->get_objects_by_attribute
    ('SIAM::ServiceComponent',
     'siam.svcc.inventory_id',
     'SRVC0002.01.u02.c01')->[0];
ok(defined($component), '$siam->get_objects_by_attribute');

### user: superuser@domain.com
note('testing the user: superuser@domain.com');
my $user1 = $siam->get_user('superuser@domain.com');
ok(defined($user1), 'get_user superuser@domain.com');


note('checking that we retrieve all contracts');
my $all_contracts = $siam->get_all_contracts();
ok(scalar(@{$all_contracts}) == 2, 'get_all_contracts') or
    diag('Expected 2 contracts, got ' . scalar(@{$all_contracts}));


note('checking that superuser@domain.com sees all contracts');
my $user1_contracts =
    $siam->get_contracts_by_user_privilege($user1, 'ViewContract');
ok(scalar(@{$all_contracts}) == scalar(@{$user1_contracts}),
   'get_contracts_by_user_privilege superuser@domain.com') or
    diag('Expected ' . scalar(@{$all_contracts}) .
         ' contracts, got ' . scalar(@{$user1_contracts}));


### user: perpetualair@domain.com
note('testing the user perpetualair@domain.com');
my $user2 = $siam->get_user('perpetualair@domain.com');
ok(defined($user1), 'get_user perpetualair@domain.com');


note('checking that perpetualair@domain.com sees only his contract');
my $user2_contracts =
    $siam->get_contracts_by_user_privilege($user2, 'ViewContract');
ok(scalar(@{$user2_contracts}) == 1,
   'get_contracts_by_user_privilege perpetualair@domain.com') or
    diag('Expected 1 contract, got ' . scalar(@{$user2_contracts}));


my $x = $user2_contracts->[0]->attr('siam.contract.inventory_id');
ok(($x eq 'INVC0001'),
   'get_contracts_by_user_privilege perpetualair@domain.com') or
    diag('Expected siam.contract.inventory_id: INVC0001, got: ' . $x);



### user: zetamouse@domain.com
note('testing the user zetamouse@domain.com');
my $user3 = $siam->get_user('zetamouse@domain.com');
ok(defined($user1), 'get_user zetamouse@domain.com');


note('checking that zetamouse@domain.com sees only his contract');
my $user3_contracts =
    $siam->get_contracts_by_user_privilege($user3, 'ViewContract');
ok(scalar(@{$user3_contracts}) == 1,
   'get_contracts_by_user_privilege zetamouse@domain.com') or
    diag('Expected 1 contract, got ' . scalar(@{$user3_contracts}));


$x = $user3_contracts->[0]->attr('siam.contract.inventory_id');
ok($x eq 'INVC0002', 'get_contracts_by_user_privilege zetamouse@domain.com') or
    diag('Expected siam.contract.inventory_id: INVC0002, got: ' . $x);


### Privileges
note('verifying privileges');
ok($user1->has_privilege('ViewContract', $user2_contracts->[0]) and
   $user1->has_privilege('ViewContract', $user3_contracts->[0]),
   'superuser@domain.com -> has_privilege') or
    diag('superuser@domain.com does not see a contract');

ok($user2->has_privilege('ViewContract', $user2_contracts->[0]) and
   $user3->has_privilege('ViewContract', $user3_contracts->[0]),
   'users see their contracts') or
    diag('one of users does not see his contract');

ok((not $user2->has_privilege('ViewContract', $user3_contracts->[0])),
   'perpetualair@domain.com should not see contracts ' .
   'of zetamouse@domain.com') or
    diag('perpetualair@domain.com sees a contract of zetamouse@domain.com');

ok((not $user3->has_privilege('ViewContract', $user2_contracts->[0])),
   'zetamouse@domain.com should not see contracts of perpetualair@domain.com')
    or
    diag('zetamouse@domain.com sees a contract of perpetualair@domain.com');



### Service units
note('testing the service units and service components');

my $services = $user2_contracts->[0]->get_services();
ok((scalar(@{$services}) == 2), 'get_services') or
    diag('Expected 2 services for INVC0001, got ' . scalar(@{$services}));

# find BIS0001 for further testing
my $s;
foreach my $obj (@{$services})
{
    if( $obj->attr('siam.svc.inventory_id') eq 'BIS0001')
    {
        $s = $obj;
        last;
    }
}
ok(defined($s)) or diag('Expected to find Service BIS0001');

my $units = $s->get_service_units();
ok((scalar(@{$units}) == 2), 'get_service_units') or
    diag('Expected 2 service units for BIS0001, got ' .
         scalar(@{$units}));

# find BIS.64876.45 for further testing
my $u;
foreach my $obj (@{$units})
{
    if( $obj->attr('siam.svcunit.inventory_id') eq 'BIS.64876.45' )
    {
        $u = $obj;
        last;
    }
}
ok(defined($u)) or diag('Expected to find Service Unit BIS.64876.45');

my $components = $u->get_components();
ok(scalar(@{$components}) == 1, 'get_components') or
    diag('Expected 1 component for SRVC0001.01.u01, got ' .
         scalar(@{$components}));

### Devices and components

my $dev = $siam->get_device('ZUR8050AN33');
ok(defined($dev)) or diag('$siam->get_device(\'ZUR8050AN33\') returned undef');

my $dc = $dev->get_components();
ok((scalar(@{$dc}) == 2), '$dev->get_components()'), or
    diag('Expected 2 device components for ZUR8050AN33, got ' .
         scalar(@{$dc}));

my $new_dc =
    [
     {
      'siam.devc.inventory_id' => 'ZUR8050AN33_p01',
      'siam.devc.type' => 'IFMIB.Port',
      'siam.devc.name' => 'GigabitEthernet0/1',
      'siam.devc.description' => 'SAP200001',
      'siam.object.complete' => 1,
     },
     {
      'siam.devc.inventory_id' => 'ZUR8050AN33_p02',
      'siam.devc.type' => 'IFMIB.Port',
      'siam.devc.name' => 'GigabitEthernet0/2',
      'siam.devc.description' => 'SAP200002',
      'siam.object.complete' => 1,
     },
     {
      'siam.devc.inventory_id' => 'ZUR8050AN33_p03',
      'siam.devc.type' => 'IFMIB.Port',
      'siam.devc.name' => 'GigabitEthernet0/3',
      'siam.devc.description' => 'SAP200001',
      'siam.object.complete' => 1,
     },
    ];

$dev->set_condition('siam.device.set_components', encode_json($new_dc));
$dc = $dev->get_components();
ok((scalar(@{$dc}) == 3), '$dev->get_components() after set_comopnents'), or
    diag('Expected 3 device components for ZUR8050AN33, got ' .
         scalar(@{$dc}));
     
$dev->set_condition('xxx.test1', 'foobar');
$dev = $siam->get_device('ZUR8050AN33');
ok(($dev->attr('xxx.test1') eq 'foobar'), 'set_condition');

              
### User privileges to see attributes
note('testing user privileges to see attributes');
my $filtered = $siam->filter_visible_attributes($user2, $u->attributes());

ok((not defined($filtered->{'xyz.serviceclass'}))) or
    diag('User perpetualair@domain.com is not supposed to see xyz.serviceclass');

ok( defined($filtered->{'xyz.access.redundant'})) or
    diag('User perpetualair@domain.com is supposed ' .
         'to see xyz.access.redundant');


### $object->contained_in()
note('testing $object->contained_in()');
my $x1 = $user2_contracts->[0]->contained_in();
ok(not defined($x1)) or
    diag('contained_in() did not return undef as expected');

my $x2 = $component->contained_in();
ok(defined($x2)) or diag('contained_in() returned undef');

ok($x2->objclass eq 'SIAM::ServiceUnit') or
    diag('contained_in() returned siam.object.class: ' . $x2->objclass);

ok($x2->attr('siam.svcunit.inventory_id') eq 'VPH.8788.99') or
    diag('contained_in() returned siam.object.id: ' . $x2->id);


### siam.contract.content_md5hash
note('testing computable: siam.contract.content_md5hash');
my $md5sum =
    $user2_contracts->[0]->computable('siam.contract.content_md5hash');
ok(defined($md5sum) and $md5sum =~ /^[0-9a-f]{32}$/) or
    diag('Computable siam.contract.content_md5hash ' .
         'returned a wrong result');

### Deep walk
my $walk_res =
    $user2_contracts->[0]->deep_walk_contained_objects('SIAM::ServiceUnit');
my $walk_count = scalar(@{$walk_res});
ok(($walk_count == 3), 'deep_walk_contained_objects') or
    diag('deep_walk_contained_objects returned ' . 
         $walk_count . ' objects, expected 3');









# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
