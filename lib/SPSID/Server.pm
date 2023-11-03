package SPSID::Server;

use utf8;
use Digest::MD5 qw(md5_hex);
use Data::UUID;
use DBIx::Sequence;
use Text::Unidecode;
use JSON;
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
        if( $@ ) {
            die($@);
        }

        $self->_backend($SPSID::Config::backend->new
                        (user_id => $self->user_id));
    }

    # build the hash of object reference attributes
    my $objrefs = {};
    foreach my $objclass (keys %{$SPSID::Config::class_attributes}) {
        my $cfg = $SPSID::Config::class_attributes->{$objclass};
        if( defined($cfg->{'attr'}) ) {
            foreach my $name (keys %{$cfg->{'attr'}}) {
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


sub ping
{
    my $self = shift;
    return $self->_backend->ping();
}


sub _fetch_object
{
    my $self = shift;
    my $id = shift;

    my $attr = $self->_backend->fetch_object($id);
    $self->_utf_tidy([$attr]);
    return $attr;
}


sub _utf_tidy
{
    my $self = shift;
    my $objects = shift;

    my $s = $self->get_schema();
    foreach my $attr (@{$objects}) {
        my $objclass = $attr->{'spsid.object.class'};
        my $attr_schema = $s->{$objclass}{'attr'};
        foreach my $name (keys %{$attr}) {
            if( not($attr_schema->{$name}{'utf8'}) ) {
                utf8::downgrade($attr->{$name});
            }
        }
    }
    return $objects;
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

    $self->ping();

    # random string to take md5 as the new object ID
    my $id_seed = scalar(localtime(time())) . rand(1e8);
    while ( my ($name, $value) = each %{$attr} ) {
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

    eval {
        $self->_backend->create_object($attr);
        if( not $cfg->{$objclass}{'nolog'} ) {
            $self->log_object($id, 'create_object', $attr);
        }
        $self->_backend->commit();
    };
    if( $@ ) {
        $self->_backend->rollback();
        die($@);
    }

    return $id;
}



# modify or add or delete attributes of an object

sub modify_object
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;

    $self->ping();
    eval {
        $self->_modify_object_impl($id, $mod_attr);
        $self->_backend->commit();
    };
    if( $@ ) {
        $self->_backend->rollback();
        die($@);
    }
    return;
}


sub _modify_object_impl
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;

    my $attr = $self->_fetch_object($id);
    my $deleted_attr = {};
    my $added_attr = {};
    my $modified_attr = {};
    my $old_attr = {};

    my $cfg = $SPSID::Config::class_attributes;
    my $objclass = $attr->{'spsid.object.class'};
    my $nolog = ($cfg->{$objclass}{'nolog'} ? 1:0);

    while (my ($name, $value) = each %{$mod_attr}) {
        if( $name eq 'spsid.object.id' or
             $name eq 'spsid.object.class' ) {

            die('SPSID::modify_object cannot modify ' . $name);
        }

        if( not defined($value) ) {
            $deleted_attr->{$name} = defined($attr->{$name}) ? $attr->{$name} : undef;
            delete $attr->{$name};
        } elsif( not defined($attr->{$name}) ) {
            $added_attr->{$name} = $value;
            $attr->{$name} = $value;
        } elsif( $value ne $attr->{$name} ) {
            $old_attr->{$name} = $attr->{$name};
            $attr->{$name} = $value;
            $modified_attr->{$name} = $value;
        }
    }

    my $clone_before_calc = {};
    while (my ($name, $value) = each %{$attr}) {
        $clone_before_calc->{$name} = $attr->{$name};
    }

    my $calc_attr = $self->get_calculated_attributes($attr);
    foreach my $name (@{$calc_attr}) {
        if( not defined($clone_before_calc->{$name}) ) {
            $added_attr->{$name} = $attr->{$name};
        } elsif( $clone_before_calc->{$name} ne $attr->{$name} ) {
            $modified_attr->{$name} = $attr->{$name};
        }
    }

    $self->validate_object($attr);
    my @del_attrs = sort keys %{$deleted_attr};
    if( scalar(@del_attrs) > 0 ) {

        $self->_backend->delete_object_attributes($id, \@del_attrs);

        if( not $nolog ) {
            foreach my $name (@del_attrs) {
                if( defined($deleted_attr->{$name}) ) {
                    $self->log_object
                        ($id, 'del_attr', {'name' => $name, 'old_val' => unidecode($deleted_attr->{$name})});
                }
            }
        }
    }

    my @add_attrs = sort keys %{$added_attr};
    if( scalar(@add_attrs) > 0 ) {

        $self->_backend->add_object_attributes($id, $added_attr);

        if( not $nolog ) {
            foreach my $name (@add_attrs) {
                $self->log_object
                    ($id, 'add_attr', {'name' => $name, 'new_val' => unidecode($added_attr->{$name})});
            }
        }
    }

    my @mod_attrs = sort keys %{$modified_attr};
    if( scalar(@mod_attrs) > 0 ) {

        $self->_backend->modify_object_attributes($id, $modified_attr);

        if( not $nolog ) {
            foreach my $name (@mod_attrs) {
                $self->log_object
                    ($id, 'mod_attr', {'name' => $name, 'old_val' => unidecode($old_attr->{$name}),
                                       'new_val' => unidecode($modified_attr->{$name})});
            }
        }
    }

    return;
}



sub modify_multiple_objects
{
    my $self = shift;
    my $mod = shift;

    $self->ping();

    eval {
        foreach my $id (keys %{$mod}) {
            $self->_modify_object_impl($id, $mod->{$id});
        }
        $self->_backend->commit();
    };
    if( $@ ) {
        $self->_backend->rollback();
        die($@);
    }
    return;
}


sub delete_object
{
    my $self = shift;
    my $id = shift;

    $self->ping();

    if( not $self->object_exists($id) ) {
        die("Object does not exist: $id");
    }

    eval {
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

        my $cfg = $SPSID::Config::class_attributes;
        if( defined($cfg->{$thisclass}) and $cfg->{$thisclass}{'delete_permanently'} ) {
            my $obj = $self->_fetch_object($id);
            my $data = {'spsid.object.class' => $obj->{'spsid.object.class'}};
            my $attrs = $cfg->{$thisclass}{'attr'};
            if( defined($attrs) ) {
                foreach my $name (keys %{$attrs}) {
                    if( ($cfg->{$name}{'unique'} or $cfg->{$name}{'unique_child'}) and defined($obj->{$name}) ) {
                        $data->{$name} = $obj->{$name};
                    }
                }
            }
            $self->log_object($obj->{'spsid.object.container'}, 'delete_child', $data);
            $self->_backend->delete_object_permanently($id);
        } else {
            if( not $cfg->{$thisclass}{'nolog'} ) {
                $self->log_object($id, 'delete_object', undef);
            }
            $self->_backend->delete_object($id);
        }

        $self->_backend->commit();
    };
    if( $@ ) {
        $self->_backend->rollback();
        die($@);
    }

    return;
}


sub get_object
{
    my $self = shift;
    my $id = shift;

    $self->ping();
    if( not $self->object_exists($id) ) {
        return undef;
    }
    my $obj = $self->_fetch_object($id);
    return $self->_retrieve_objrefs($obj->{'spsid.object.class'}, [$obj])->[0];
}


sub get_object_log
{
    my $self = shift;
    my $id = shift;

    $self->ping();
    return $self->_backend->get_object_log($id);
}



sub get_last_change_id
{
    my $self = shift;
    $self->ping();
    return $self->_backend->get_last_change_id();
}


sub get_last_changes
{
    my $self = shift;
    my $start_id = shift;
    my $max_rows = shift;

    $self->ping();
    return $self->_backend->get_last_changes($start_id, $max_rows);
}





sub _obj_sort_name
{
    my $self = shift;
    my $attr = shift;

    my $objclass = $attr->{'spsid.object.class'};
    my $s = $self->get_schema();

    if( not defined($s->{$objclass}) or
         not defined($s->{$objclass}{'display'}) ) {
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
         scalar(@{$prop->{'descr_attr'}}) > 0 ) {
        my @parts;
        foreach my $attr_name (@{$prop->{'descr_attr'}}) {
            push(@parts, $attr->{$attr_name});
        }

        return join(' ', @parts);
    }

    return $attr->{'spsid.object.id'};
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


# if an obect contains objrefs, we fetch them non-recursively
sub _retrieve_objrefs
{
    my $self = shift;
    my $objclass = shift;
    my $objects = shift;

    my @objref_attrs;
    my $s = $self->get_schema();
    my $attr_schema = $s->{$objclass}{'attr'};
    if( defined($attr_schema) ) {
        foreach my $name (keys %{$attr_schema}) {
            if( defined($attr_schema->{$name}{'objref'}) ) {
                push(@objref_attrs, $name);
            }
        }
    }

    if( scalar(@objref_attrs) > 0 ) {
        foreach my $obj (@{$objects}) {
            foreach my $name (@objref_attrs) {
                if( defined($obj->{$name}) ) {
                    if( $obj->{$name} ne 'NIL' ) {
                        $obj->{$name} = $self->_fetch_object($obj->{$name});
                    }
                    else {
                        $obj->{$name} = {};
                    }
                }
            }
        }
    }

    return $objects;
}



# input: attribute names and values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    if( scalar(@_) % 2 != 0 ) {
        die('Odd number of attributes and values in search_objects()');
    }

    $self->ping();

    my $results = [];
    if( scalar(@_) == 0 ) {
        $results = $self->_sort_objects($self->_utf_tidy($self->_backend->contained_objects($container, $objclass)));
    } else {
        my $firstmatch = 1;
        while ( scalar(@_) > 0 ) {
            my $name = shift;
            my $value = shift;

            if( $firstmatch ) {
                $results =
                    $self->_utf_tidy($self->_backend->search_objects($container, $objclass,
                                                                     $name, $value));
                $firstmatch = 0;
            } elsif( scalar(@{$results}) > 0 ) {
                my $old_results = $results;
                $results = [];

                foreach my $obj (@{$old_results}) {
                    if( defined($obj->{$name}) and $obj->{$name} eq $value ) {
                        push(@{$results}, $obj);
                    }
                }
            }
        }

        $results = $self->_sort_objects($results);
    }

    return $self->_retrieve_objrefs($objclass, $results);
}


# case insensitive attribute prefix search
sub search_prefix
{
    my $self = shift;
    my $objclass = shift;
    my $attr_name = shift;
    my $attr_prefix = shift;

    $self->ping();
    my $results = $self->_sort_objects
        ($self->_utf_tidy($self->_backend->search_prefix($objclass, $attr_name, $attr_prefix)));
    return $self->_retrieve_objrefs($objclass, $results);
}


sub search_fulltext
{
    my $self = shift;
    my $objclass = shift;
    my $search_string = shift;

    $self->ping();

    my $attrlist = [];
    my $s = $self->get_schema();

    if( defined($s->{$objclass}) and
         defined($s->{$objclass}{'display'}) and
         defined($s->{$objclass}{'display'}{'fullsearch_attr'}) ) {
        push( @{$attrlist}, @{$s->{$objclass}{'display'}{'fullsearch_attr'}} );
    }

    if( scalar(@{$attrlist}) == 0 ) {
        return [];
    }

    my $results = $self->_sort_objects
        ($self->_utf_tidy($self->_backend->search_fulltext($objclass,
                                                           $search_string, $attrlist)));
    return $self->_retrieve_objrefs($objclass, $results);
}


sub get_attr_values
{
    my $self = shift;
    my $objclass = shift;
    my $attr_name = shift;

    my $values = $self->_backend->get_attr_values($objclass,$attr_name);

    my $s = $self->get_schema();
    my $attr_schema = $s->{$objclass}{'attr'};
    if( not($attr_schema->{$attr_name}{'utf8'}) ) {
        for(my $i = 0; $i < scalar(@{$values}); $i++) {
            utf8::downgrade($values->[$i]);
        }
    }
    return [sort @{$values}];
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

    if( defined($SPSID::Config::class_attributes->{$objclass}{'attr'}) ) {
        my $cfg = $SPSID::Config::class_attributes->{$objclass}{'attr'};

        foreach my $name (keys %{$cfg}) {
            if( defined($cfg->{$name}{'templatemember'}) ) {
                my $template_active = 0;
                while ( my ($templatekeyattr, $keyvalues) =
                        each %{$cfg->{$name}{'templatemember'}} ) {
                    if( defined($templatekeys->{$templatekeyattr}) ) {
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

    foreach my $name (keys %{$attr_schema}) {
        if( defined($attr_schema->{$name}{'default'}) ) {
            $attr->{$name} = $attr_schema->{$name}{'default'};
        } elsif( $attr_schema->{$name}{'default_autogen'} ) {
            $attr->{$name} = $ug->create_str();
        } elsif( defined($attr_schema->{$name}{'objref'}) ) {
            $attr->{$name} = 'NIL';
        }
    }

    if( defined($SPSID::Config::new_obj_generators) and
         defined($SPSID::Config::new_obj_generators->{$objclass}) ) {
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

    foreach my $name (keys %{$attr_schema}) {
        if( $attr_schema->{$name}{'calculated'} ) {
            $attr->{$name} = '';
            $attrlist->{$name} = 1;
        }
    }

    if( defined($SPSID::Config::calc_attr_generators) and
         defined($SPSID::Config::calc_attr_generators->{$objclass}) ) {
        foreach my $func
            (values %{$SPSID::Config::calc_attr_generators->{$objclass}}) {

            my $gen_attr_list = &{$func}($self, $attr);
            if( defined($gen_attr_list) ) {
                foreach my $name (keys %{$gen_attr_list}) {
                    if( not defined($attr->{$name}) ) {
                        die('Calculated attribute ' . $name . ' is undefined for ' .
                            $attr->{'spsid.object.id'});
                    }
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

    foreach my $name ('spsid.object.class', 'spsid.object.container') {
        my $value = $attr->{$name};
        if( not defined($value) ) {
            die('Missing mandatory attribute ' . $name . ' in ' .
                $attr->{'spsid.object.id'});
        } elsif( $value eq '' ) {
            die('Mandatory attribute ' . $name .
                ' cannot have empty value in ' .
                $attr->{'spsid.object.id'});
        }
    }

    if( $attr->{'spsid.object.container'} ne 'NIL' and
         not $self->_backend->object_exists($attr->{'spsid.object.container'}) ) {
        die('Container object ' . $attr->{'spsid.object.container'} .
            ' does not exist for ' .  $attr->{'spsid.object.id'});
    }

    foreach my $func (values %{$SPSID::Config::object_validators}) {
        &{$func}($attr);
    }

    my $objclass = $attr->{'spsid.object.class'};

    my $cfg = $SPSID::Config::class_attributes;
    if( defined($cfg->{$objclass}) ) {
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

    foreach my $name (keys %{$cfg}) {
        next if $cfg->{$name}{'calculated'};

        my $value = $attr->{$name};

        if( defined($cfg->{$name}{'templatemember'}) ) {
            my $template_active = 0;
            foreach my $templatekeyattr
                (keys %{$cfg->{$name}{'templatemember'}})  {

                if( defined($attr->{$templatekeyattr}) ) {
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
                } else {
                    next;
                }
            }
        }

        if( defined($cfg->{$name}{'dictionary'}) and defined($value) ) {
            if( not grep {$value eq $_} @{$cfg->{$name}{'dictionary'}} ) {
                die('Attribute ' . $name . ' is a dictionary attribute, ' .
                    'but the value ' . $value . ' is outside of dictionary ' .
                    'in ' . $attr->{'spsid.object.id'});
            }
        }

        if( defined($cfg->{$name}{'regexp'}) and defined($value) ) {
            if( $value !~ $cfg->{$name}{'regexp'} ) {
                die('Attribute ' . $name . ' in ' . $attr->{'spsid.object.id'} . '(' . $value . ')' .
                    ' does not match the regexp: ' . $cfg->{$name}{'regexp'});
            }
        }

        if( $cfg->{$name}{'mandatory'} ) {
            if( not defined($value) ) {
                die('Missing mandatory attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            } elsif( $value eq '' ) {
                die('Mandatory attribute ' . $name .
                    ' cannot have empty value in ' .
                    $attr->{'spsid.object.id'});
            }
        }

        if( $cfg->{$name}{'unique'} and defined($value) ) {
            my $found =
                $self->search_objects(undef,
                                      $attr->{'spsid.object.class'},
                                      $name,
                                      $value);

            if( scalar(@{$found}) > 0 and
                 ( $found->[0]->{'spsid.object.id'} ne
                   $attr->{'spsid.object.id'} ) ) {
                die('Duplicate value "' . $value .
                    '" for a unique attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
        }

        if( $cfg->{$name}{'unique_child'} and defined($value) and
             (not defined($cfg->{$name}{'objref'}) or $value ne 'NIL') ) {
            my $found =
                $self->search_objects($attr->{'spsid.object.container'},
                                      $attr->{'spsid.object.class'},
                                      $name,
                                      $value);

            if( scalar(@{$found}) > 0 and
                 ( $found->[0]->{'spsid.object.id'} ne
                   $attr->{'spsid.object.id'} ) ) {
                die('Duplicate value "' . $value .
                    '" within the container for a unique_child attribute ' .
                    $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
        }

        if( defined($cfg->{$name}{'objref'}) and
             defined($value) and $value ne 'NIL' ) {
            my $refclass = $cfg->{$name}{'objref'};

            if( not $cfg->{$name}{'reserved_refs'}{$value} ) {
                if( not $self->object_exists($value) ) {
                    die('Attribute ' . $name .
                        ' points to a non-existent object ' . $value .
                        ' in ' . $attr->{'spsid.object.id'});
                }

                if( $refclass ne '*' ) {
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

    foreach my $objclass ( sort @{$self->contained_classes($id)} ) {
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
    my $event = shift;
    my $data = shift;
    my $app = shift;

    my $msg = encode_json({'event' => $event, 'data' => $data});

    $self->_backend->log_object($id, $self->user_id, $msg, $app);

    my $logger = $self->logger;
    if( defined($logger) ) {
        $logger->info($id . ':' . $self->user_id . ': ' . $msg);
    }

    return;
}


sub add_application_log
{
    my $self = shift;
    my $id = shift;
    my $app = shift;
    my $userid = shift;
    my $msg = shift;

    $self->_backend->log_object($id, $userid, encode_json({'event' => 'message', 'data' => $msg}), $app);

    my $logger = $self->logger;
    if( defined($logger) ) {
        $logger->info($id . ' - ' . $app . ' - ' . $userid . ': ' . $msg);
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
