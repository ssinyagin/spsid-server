# All site-specific SPSID configuration goes here

$SPSID::Config::Backend::SQL::dbi_dsn =
    'dbi:SQLite:dbname=' . $ENV{SPSID_SQLITE_DB};

$SPSID::Config::Backend::SQL::dbi_user = '';
$SPSID::Config::Backend::SQL::dbi_password = '';


$SPSID::Config::calc_attr_generators->{'SIAM::ServiceComponent'}{'t1'} =
    sub {
        my $self = shift;
        my $attr = shift;

        my $ret = {};
        my $svctype = $attr->{'siam.svcc.type'};
        my $invid = $attr->{'siam.svcc.inventory_id'};

        $attr->{'test.calc'} = $svctype . '--' . $invid ;
        $ret->{'test.calc'} = 1;
        
        return $ret;
    };

# test a mandatory template member
$SPSID::Config::class_attributes->{'SIAM::DeviceComponent'}->{
    'attr'}->{'vm.ram'} =
{
    'templatemember' => {'siam.devc.type' => ['HOST']},
    'descr' => 'VM RAM size in MB',
    'mandatory' => 1,
};
                
push(@{$SPSID::Config::class_attributes->{'SIAM::DeviceComponent'}->{
    'attr'}->{'siam.devc.type'}{'dictionary'}}, 'HOST');


push(@{$SPSID::Config::class_attributes->{'SIAM::ServiceComponent'}->{
    'attr'}->{'siam.svcc.type'}{'dictionary'}}, 'HOST');


1;

