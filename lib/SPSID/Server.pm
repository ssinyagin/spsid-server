package SPSID::Server;

use utf8;
use Digest::MD5 qw(md5_hex);
use Data::UUID;
use DBIx::Sequence;
use Text::Unidecode;

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
        $id_seed .= $name . ':' . unidecode($value);
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
    $self->get_calculated_attributes($attr);
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

    my $clone_before_calc = {};
    while(my ($name, $value) = each %{$attr}) {
        $clone_before_calc->{$name} = $attr->{$name};
    }
        
    my $calc_attr = $self->get_calculated_attributes($attr);
    foreach my $name (@{$calc_attr}) {
        if( not defined($clone_before_calc->{$name}) ) {
            $added_attr->{$name} = $attr->{$name};
        }
        elsif( $clone_before_calc->{$name} ne $attr->{$name} ) {
            $modified_attr->{$name} = $attr->{$name};
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


sub _obj_sort_name
{
    my $self = shift;
    my $attr = shift;

    my $objclass = $attr->{'spsid.object.class'};
    my $s = $self->get_schema();

    if( not defined($s->{$objclass}) or
        not defined($s->{$objclass}{'display'}) )
    {
        return $attr->{'spsid.object.id'};
    }

    my $prop = $s->{$objclass}{'display'};

    if( defined($prop->{'display.sort.string'}) ) {
        return $attr->{$prop->{'display.sort.string'}};
    }
    
    if( defined($prop->{'name_attr'}) ) {
        return $attr->{$prop->{'name_attr'}};
    }

    if( defined($prop->{'descr_attr'}) and
        scalar(@{$prop->{'descr_attr'}}) > 0 )
    {
        my @parts;
        foreach my $attr_name (@{$prop->{'descr_attr'}}) {
            push(@parts, $attr->{$attr_name});
        }

        return join(' ', @parts);
    }

    $attr->{'spsid.object.id'};
}
    
        

sub _sort_objects
{
    my $self = shift;
    my $unsorted = shift;

    my $sorted = [];
   
    push(@{$sorted},
         sort {$self->_obj_sort_name($a) cmp $self->_obj_sort_name($b)}
         @{$unsorted});

    return $sorted;
}


# input: attribute names and values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    if( scalar(@_) == 0 ) {
        return $self->_sort_objects
            ( $self->_backend->contained_objects($container, $objclass) );
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

    return $self->_sort_objects($results);
}


# case insensitive attribute prefix search
sub search_prefix
{
    my $self = shift;
    my $objclass = shift;
    my $attr_name = shift;
    my $attr_prefix = shift;

    return $self->_sort_objects
        ($self->_backend->search_prefix($objclass,$attr_name, $attr_prefix));
}

sub search_fulltext
{
    my $self = shift;
    my $objclass = shift;
    my $search_string = shift;

    my $attrlist = [];
    my $s = $self->get_schema();

    if( defined($s->{$objclass}) and
        defined($s->{$objclass}{'display'}) and
        defined($s->{$objclass}{'display'}{'fullsearch_attr'}) )
    {
        push( @{$attrlist}, @{$s->{$objclass}{'display'}{'fullsearch_attr'}} );
    }

    if( scalar(@{$attrlist}) == 0 )
    {
        return [];
    }
    
    return $self->_sort_objects
        ($self->_backend->search_fulltext($objclass,
                                          $search_string, $attrlist));
}
        
    


sub contained_classes
{
    my $self = shift;
    my $container = shift;

    my $result = $self->_backend->contained_classes($container);

    my $sorted = [];
    my $s = $self->get_schema();
    
    push(@{$sorted},
         sort {( defined($s->{$a}{'display'}{'sequence'}) and
                 defined($s->{$b}{'display'}{'sequence'}) )
                   ?
                       ($s->{$a}{'display'}{'sequence'} -
                        $s->{$b}{'display'}{'sequence'})
                           :
                               ($a cmp $b)} @{$result});    
    return $sorted;
}


sub get_schema
{
    my $self = shift;
    return $SPSID::Config::class_attributes;
}



sub get_objclass_schema
{
    my $self = shift;
    my $objclass = shift;
    my $templatekeys = shift;

    my $attr_schema = {};
    
    if( defined($SPSID::Config::class_attributes->{$objclass}{'attr'}) )
    {
        my $cfg = $SPSID::Config::class_attributes->{$objclass}{'attr'};

        foreach my $name (keys %{$cfg})
        {
            if( defined($cfg->{$name}{'templatemember'}) )
            {
                my $template_active = 0;
                while( my ($templatekeyattr, $keyvalues) =
                       each %{$cfg->{$name}{'templatemember'}} )
                {
                    if( defined($templatekeys->{$templatekeyattr}) )
                    {
                        my $key = $templatekeys->{$templatekeyattr};
                        if( grep {$key eq $_} @{$keyvalues} ) {
                            $template_active = 1;
                        }
                    }

                    last if $template_active;
                }
                
                next unless $template_active;
            }

            $attr_schema->{$name} = $cfg->{$name};
        }
    }

    return $attr_schema;
}




sub new_object_default_attrs
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;
    my $templatekeys = shift;
    
    my $attr =
    {
     'spsid.object.class' => $objclass,
     'spsid.object.container' => $container,
    };

    foreach my $name (keys %{$templatekeys}) {
        $attr->{$name} = $templatekeys->{$name};
    }
    
    my $ug = new Data::UUID;

    my $attr_schema = $self->get_objclass_schema($objclass, $templatekeys);
    
    foreach my $name (keys %{$attr_schema})
    {
        if( defined($attr_schema->{$name}{'default'}) ) {
            $attr->{$name} = $attr_schema->{$name}{'default'};
        }
        elsif( $attr_schema->{$name}{'default_autogen'} ) {
            $attr->{$name} = $ug->create_str();
        }
        elsif( defined($attr_schema->{$name}{'objref'}) ) {
            $attr->{$name} = 'NIL';
        }
    }

    if( defined($SPSID::Config::new_obj_generators) and
        defined($SPSID::Config::new_obj_generators->{$objclass}) )
    {
        foreach my $func
            (values %{$SPSID::Config::new_obj_generators->{$objclass}}) {
            &{$func}($self, $attr);
        }
    }
        
    return $attr;
}
            

# updates the attributes with calculated values
# returns arrayref with attribute names

sub get_calculated_attributes
{
    my $self = shift;
    my $attr = shift;

    my $objclass = $attr->{'spsid.object.class'};
    my $attr_schema = $self->get_objclass_schema($objclass, $attr);

    my $attrlist = {};
    
    foreach my $name (keys %{$attr_schema})
    {
        if( $attr_schema->{$name}{'calculated'} )
        {
            $attr->{$name} = '';
            $attrlist->{$name} = 1;
        }
    }

    if( defined($SPSID::Config::calc_attr_generators) and
        defined($SPSID::Config::calc_attr_generators->{$objclass}) )
    {
        foreach my $func
            (values %{$SPSID::Config::calc_attr_generators->{$objclass}}) {

            my $gen_attr_list = &{$func}($self, $attr);
            if( defined($gen_attr_list) )
            {
                foreach my $name (keys %{$gen_attr_list}) {
                    $attrlist->{$name} = 1;
                }
            }
        }
    }
    
    return [keys %{$attrlist}];
}
    


sub validate_object
{
    my $self = shift;
    my $attr = shift;

    foreach my $name ('spsid.object.class', 'spsid.object.container')
    {
        my $value = $attr->{$name};
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

    
    foreach my $func (values %{$SPSID::Config::object_validators}) {
        &{$func}($attr);
    }
    
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
        next if $cfg->{$name}{'calculated'};

        my $value = $attr->{$name};

        if( defined($cfg->{$name}{'templatemember'}) )
        {
            my $template_active = 0;
            foreach my $templatekeyattr
                (keys %{$cfg->{$name}{'templatemember'}})  {

                if( defined($attr->{$templatekeyattr}) )
                {
                    my $keyvalues =
                        $cfg->{$name}{'templatemember'}{$templatekeyattr};
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

        if( $cfg->{$name}{'unique_child'} and defined($value) )
        {
            my $found =
                $self->search_objects($attr->{'spsid.object.container'},
                                      $attr->{'spsid.object.class'},
                                      $name,
                                      $value);
            
            if( scalar(@{$found}) > 0 and
                ( $found->[0]->{'spsid.object.id'} ne
                  $attr->{'spsid.object.id'} ) )
            {
                die('Duplicate value "' . $value .
                    '" within the container for a unique_child attribute ' .
                    $name . ' in ' .
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


sub recursive_md5
{
    my $self = shift;
    my $id = shift;

    my $md5 = new Digest::MD5;
    $self->_calc_recursive_md5($id, $md5);
    
    return $md5->hexdigest();
}


sub _calc_recursive_md5
{
    my $self = shift;
    my $id = shift;
    my $md5 = shift;
    my $attr = shift;

    if( not defined($attr) ) {
        $attr = $self->get_object($id);
    }

    foreach my $name (sort keys %{$attr}) {
        $md5->add('#' . $name . '//' . unidecode($attr->{$name}) . '#');
    }

    foreach my $objclass ( sort @{$self->contained_classes($id)} )
    {
        foreach my $obj
            ( sort {$a->{'spsid.object.id'} cmp $b->{'spsid.object.id'}}
              @{$self->search_objects($id, $objclass)} ) {
            
            $self->_calc_recursive_md5($obj->{'spsid.object.id'},
                                       $md5, $obj);
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



sub sequence_next
{
    my $self = shift;
    my $realm = shift;
    return $self->_backend->sequence_next($realm);
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
