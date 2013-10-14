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

        if( $svctype eq 'IFMIB.Port' ) {
            $attr->{'torrus.port.nodeid'} = 'spsid-port//' . $invid ;
            $ret->{'torrus.port.nodeid'} = 1;
        }
        elsif( $svctype eq 'Power.PDU' ) {
            $attr->{'torrus.power.nodeid'} = 'spsid-pdu//' . $invid ;
            $ret->{'torrus.power.nodeid'} = 1;
        }
        elsif( $svctype eq 'HOST.Virtual' ) {
            $attr->{'torrus.host.nodeid'} = 'spsid-host//' . $invid ;
            $ret->{'torrus.host.nodeid'} = 1;
        }
        
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
                


1;

