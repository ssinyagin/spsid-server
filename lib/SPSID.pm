package SPSID;

use Digest::MD5 qw(md5_hex);

use Moose;

has 'user_id' =>
    (
     is  => 'rw',
     isa => 'Str',
     default => 'nobody',
    );


has 'logger' =>
    (
     is  => 'rw',
     isa => 'Object',
    );
    

has '_backend' =>
    (
     is  => 'rw',
     isa => 'Object',
     init_arg => undef,
     handles => {
                 connect    => 'connect',
                 disconnect => 'disconnect'},
    );



sub BUILD
{
    my $self = shift;

    if( not defined($self->_backend) ) {
        if( not defined($SPSID::Config::backend) ) {
            die('$SPSID::Config::backend is undefined');
        }
        
        eval(sprintf('require %s', $SPSID::Config::backend));
        if( $@ )
        {
            die($@);
        }
        
        $self->_backend($SPSID::Config::backend->new
                        (user_id => $self->user_id));
    }
    return;
}



sub object_exists
{
    my $self = shift;
    my $id = shift;

    return $self->_backend->object_exists($id);
}



sub create_object
{
    my $self = shift;
    my $objclass = shift;
    my $attr = shift;

    # random string to take md5 as the new object ID
    my $id_seed = scalar(localtime(time())) . rand(1e8);
    while( my ($name, $value) = each %{$attr} ) {
        $id_seed .= $name . ':' . $value;
    }

    my $id = md5_hex($id_seed);

    if( $self->object_exists($id) ) {
        die('Something really wrong happened: object id ' . $id .
            ' already exists in the database');
    }

    $attr->{'spsid.object.id'} = $id;
    $attr->{'spsid.object.class'} = $objclass;

    my $cfg = $SPSID::Config::class_attributes;
    if( defined($cfg->{$objclass}) and
        $cfg->{$objclass}{'single_instance'} ) {        
        my $r = $self->search_objects(undef, $objclass);
        if( scalar(@{$r}) > 0 ) {
            die('Only one instance of object class ' . $objclass .
                ' is allowed');
        }
    }

    $self->validate_object($attr);

    $self->_backend->create_object($attr);

    $self->log_object($id, 'Object created');

    return $id;
}



# modify or add or delete attributes of an object

sub modify_object
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;

    my $attr = $self->_backend->fetch_object($id);
    my $deleted_attr = {};
    my $added_attr = {};
    my $modified_attr = {};
    my $old_attr = {};

    while(my ($name, $value) = each %{$mod_attr}) {
        if( $name eq 'spsid.object.id' or
            $name eq 'spsid.object.class' ) {

            die('SPSID::modify_object cannot modify ' . $name);
        }

        if( not defined($value) and defined($attr->{$name})) {

            $deleted_attr->{$name} = $attr->{$name};
            delete $attr->{$name};
        }
        elsif( not defined($attr->{$name}) ) {

            $added_attr->{$name} = $value;
            $attr->{$name} = $value;
        }
        elsif( $value ne $attr->{$name} ) {

            $old_attr->{$name} = $attr->{$name};
            $attr->{$name} = $value;
            $modified_attr->{$name} = $value;
        }
    }

    $self->validate_object($attr);

    my @del_attrs = sort keys %{$deleted_attr};
    if( scalar(@del_attrs) > 0 ) {

        $self->_backend->delete_object_attributes($id, \@del_attrs);

        foreach my $name (@del_attrs) {

            $self->log_object
                ($id,
                 'Deleted attribute: ' . $name .
                 ', value: ' . $deleted_attr->{$name});
        }
    }

    my @add_attrs = sort keys %{$added_attr};
    if( scalar(@add_attrs) > 0 ) {

        $self->_backend->add_object_attributes($id, $added_attr);

        foreach my $name (@add_attrs) {

            $self->log_object
                ($id,
                 'Added attribute: ' . $name .
                 ', value: ' . $added_attr->{$name});
        }
    }

    my @mod_attrs = sort keys %{$modified_attr};
    if( scalar(@mod_attrs) > 0 ) {

        $self->_backend->modify_object_attributes($id, $modified_attr);

        foreach my $name (@mod_attrs) {

            $self->log_object
                ($id,
                 'Modified attribute: ' . $name .
                 ', old value: ' . $old_attr->{$name} .
                 ', new value: ' . $modified_attr->{$name});
        }
    }
    return;
}



sub delete_object
{
    my $self = shift;
    my $id = shift;

    if( not $self->object_exists($id) ) {
        die("Object does not exist: $id");
    }

    # recursively delete all contained objects

    foreach my $objclass ( @{$self->contained_classes($id)} ) {
        foreach my $obj ( @{$self->search_objects($id, $objclass)} ) {
            $self->delete_object($obj->{'spsid.object.id'});
        }
    }
    
    $self->log_object($id, 'Object deleted');
    $self->_backend->delete_object($id);
    return;
}


sub get_object
{
    my $self = shift;
    my $id = shift;

    return $self->_backend->fetch_object($id);
}


# input: attribute names and values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    if( scalar(@_) == 0 ) {
        return $self->_backend->contained_objects($container, $objclass);
    }

    if( scalar(@_) % 2 != 0 ) {
        die('Odd number of attributes and values in search_objects()');
    }

    my $results = [];

    while( scalar(@_) > 0 ) {
        my $name = shift;
        my $value = shift;

        if( scalar(@{$results}) == 0 ) {
            $results =
                $self->_backend->search_objects($container, $objclass,
                                                $name, $value);
        }
        else {
            my $old_results = $results;
            $results = [];

            foreach my $obj (@{$old_results}) {
                if( defined($obj->{$name}) and $obj->{$name} eq $value ) {
                    push(@{$results}, $obj);
                }
            }
        }
    }

    return $results;
}


# case insensitive attribute prefix search
sub search_prefix
{
    my $self = shift;
    my $objclass = shift;
    my $attr_name = shift;
    my $attr_prefix = shift;

    return $self->_backend->search_prefix($objclass,$attr_name, $attr_prefix);
}


sub contained_classes
{
    my $self = shift;
    my $container = shift;

    return $self->_backend->contained_classes($container);
}


sub get_schema
{
    my $self = shift;
    return $SPSID::Config::class_attributes;
}



sub validate_object
{
    my $self = shift;
    my $attr = shift;

    foreach my $func (@SPSID::Config::object_validators) {
        &{$func}($attr);
    }

    $self->_verify_attributes($attr, $SPSID::Config::common_attributes);

    my $objclass = $attr->{'spsid.object.class'};

    my $cfg = $SPSID::Config::class_attributes;
    if( defined($cfg->{$objclass}) ) {
        $self->_verify_attributes($attr, $cfg->{$objclass});

        if( defined($cfg->{$objclass}{'contained_in'}) ) {
            my $container_class =
                $self->_backend->object_class
                    ($attr->{'spsid.object.container'});

            if( not $cfg->{$objclass}{'contained_in'}{$container_class} ) {
                die('Object ' . $attr->{'spsid.object.id'} .
                    ' of class ' . $objclass . ' cannot be contained inside ' .
                    'of an object of class ' . $container_class);
            }
        }
    }
    
    return;
}



sub _verify_attributes
{
    my $self = shift;
    my $attr = shift;
    my $cfg = shift;

    if( defined($cfg->{'mandatory'}) ) {
        foreach my $name (keys %{$cfg->{'mandatory'}}) {
            if( $cfg->{'mandatory'}{$name} and not defined($attr->{$name}) ) {
                die('Missing mandatory attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
        }
    }

    if( defined($cfg->{'unique'}) ) {
        foreach my $name (keys %{$cfg->{'unique'}}) {
            if( $cfg->{'unique'}{$name} and 
                defined($attr->{$name}) ) {
                my $found =
                    $self->search_objects(undef,
                                          $attr->{'spsid.object.class'},
                                          $name,
                                          $attr->{$name});
                
                if( scalar(@{$found}) > 0 and
                    ( $found->[0]->{'spsid.object.id'} ne
                      $attr->{'spsid.object.id'} ) ) {

                    die('Duplicate value "' . $attr->{$name} .
                        '" for a unique attribute ' . $name . ' in ' .
                        $attr->{'spsid.object.id'});
                }
            }
        }
    }

    if( defined($cfg->{'object_ref'}) ) {
        foreach my $name (keys %{$cfg->{'object_ref'}}) {
            if( defined($attr->{$name}) and $attr->{$name} ne 'NIL' ) {

                my $target = $attr->{$name};
                my $refclass = $cfg->{'object_ref'}{$name};
                
                if( not $cfg->{'reserved_refs'}{$name}{$target} ) {
                    
                    if( not $self->object_exists($target) ) {
                        die('Attribute ' . $name .
                            ' points to a non-existent object ' . $target .
                            ' in ' . $attr->{'spsid.object.id'});
                    }
                    
                    if( $refclass ne '*' ) {
                        my $target_class =
                            $self->_backend->object_class($target);
                        
                        if( $target_class ne $refclass ) {
                            die('Attribute ' . $name .
                                ' points to an object ' . $target .
                                ' of class ' . $target_class . ', but is only' .
                                ' allowed to point to ' . $refclass .
                                ' in ' . $attr->{'spsid.object.id'});
                        }
                    }
                }
            }
        }
    }
    
    return;
}






sub log_object
{
    my $self = shift;
    my $id = shift;
    my $msg = shift;

    $self->_backend->log_object($id, $self->user_id, $msg);

    my $logger = $self->logger;
    if( defined($logger) ) {
        $logger->info($id . ':' . $self->user_id . ': ' . $msg);
    }

    return;
}


sub clear_user_id
{
    my $self = shift;
    $self->user_id('nobody');
}


    


1;



# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
