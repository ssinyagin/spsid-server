package SPSID::Server;

use utf8;
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


has '_objrefs' =>
    (
     is  => 'rw',
     isa => 'HashRef',
     init_arg => undef,
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

    # build the hash of object reference attributes
    my $objrefs = {};    
    foreach my $objclass (keys %{$SPSID::Config::class_attributes}) {
        my $cfg = $SPSID::Config::class_attributes->{$objclass};
        if( defined($cfg->{'attr'}) )
        {
            foreach my $name (keys %{$cfg->{'attr'}})
            {
                my $ref = $cfg->{'attr'}{$name};
                
                if( defined($ref->{'objref'}) ) {
                    my $target_class = $ref->{'objref'};
                    $objrefs->{$target_class}{$objclass}{$name} = 1;
                }
            }
        }                
    }

    $self->_objrefs($objrefs);
    
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

    # set all references to this object to NIL
    my $thisclass = $self->_backend->object_class($id);
    my $objrefs = $self->_objrefs;

    foreach my $target_class ('*', $thisclass) {
        if( defined($objrefs->{$target_class}) ) {
            foreach my $objclass (keys %{$objrefs->{$target_class}}) {
                foreach my $attr_name
                    (keys %{$objrefs->{$target_class}{$objclass}}) {
                    my $r = $self->search_objects(undef, $objclass,
                                                  $attr_name, $id);
                    foreach my $obj (@{$r}) {
                        $self->modify_object($obj->{'spsid.object.id'},
                                             {$attr_name => 'NIL'});
                    }
                }
            }
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


sub get_object_log
{
    my $self = shift;
    my $id = shift;

    return $self->_backend->get_object_log($id);
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

    foreach my $func (values %{$SPSID::Config::object_validators}) {
        &{$func}($attr);
    }

    $self->_verify_attributes($attr, $SPSID::Config::common_attributes);

    my $objclass = $attr->{'spsid.object.class'};

    my $cfg = $SPSID::Config::class_attributes;
    if( defined($cfg->{$objclass}) )
    {
        if( defined($cfg->{$objclass}{'attr'}) ) {
            $self->_verify_attributes($attr, $cfg->{$objclass}{'attr'});
        }
        
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

    foreach my $name (keys %{$cfg})
    {
        my $value = $attr->{$name};
        
        if( defined($cfg->{$name}{'templatemember'}) )
        {
            my $template_active = 0;
            while( my ($templatekeyattr, $keyvalues) =
                   each %{$cfg->{$name}{'templatemember'}} )
            {
                if( defined($attr->{$templatekeyattr}) )
                {
                    my $key = $attr->{$templatekeyattr};
                    if( grep {$key eq $_} @{$keyvalues} ) {
                        $template_active = 1;
                    }
                }                        
            }

            if( not $template_active ) {
                if( defined($value) ) {
                    die('Attribute ' . $name . ' is a template member, ' .
                        'but none of template keys matched in ' .
                        $attr->{'spsid.object.id'});
                }
                else {
                    next;
                }
            }
        }

        if( defined($cfg->{$name}{'dictionary'}) and defined($value) )
        {
            if( not grep {$value eq $_} @{$cfg->{$name}{'dictionary'}} ) {
                die('Attribute ' . $name . ' is a dictionary attribute, ' .
                    'but the value ' . $value . ' is outside of dictionary ' .
                    'in ' . $attr->{'spsid.object.id'});
            }
        }                

        if( $cfg->{$name}{'mandatory'} )
        {
            if( not defined($value) ) {
                die('Missing mandatory attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
            elsif( $value eq '' ) {
                die('Mandatory attribute ' . $name .
                    ' cannot have empty value in ' .
                    $attr->{'spsid.object.id'});
            }
        }
    
        if( $cfg->{$name}{'unique'} and defined($value) )
        {
            my $found =
                $self->search_objects(undef,
                                      $attr->{'spsid.object.class'},
                                      $name,
                                      $value);
            
            if( scalar(@{$found}) > 0 and
                ( $found->[0]->{'spsid.object.id'} ne
                  $attr->{'spsid.object.id'} ) )
            {
                die('Duplicate value "' . $value .
                    '" for a unique attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
        }
    
        if( defined($cfg->{$name}{'objref'}) and
            defined($value) and $value ne 'NIL' )
        {
            my $refclass = $cfg->{$name}{'objref'};
            
            if( not $cfg->{$name}{'reserved_refs'}{$value} )
            {
                if( not $self->object_exists($value) ) {
                    die('Attribute ' . $name .
                        ' points to a non-existent object ' . $value .
                        ' in ' . $attr->{'spsid.object.id'});
                }
                
                if( $refclass ne '*' )
                {
                    my $target_class =
                        $self->_backend->object_class($value);
                    
                    if( $target_class ne $refclass ) {
                        die('Attribute ' . $name .
                            ' points to an object ' . $value .
                            ' of class ' . $target_class . ', but is only' .
                            ' allowed to point to ' . $refclass .
                            ' in ' . $attr->{'spsid.object.id'});
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
