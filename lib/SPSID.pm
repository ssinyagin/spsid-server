package SPSID;

use warnings;
use strict;

use Digest::MD5 qw(md5_hex);



sub new
{
    my $class = shift;
    my $options = shift;

    if( not defined($options->{'user'}) ) {
        die('SPSID::new requires a user ID');
    }

    if( not defined($SPSID::Config::backend) ) {
        die('$SPSID::Config::backend is undefined');
    }

    require $SPSID::Config::backend;
    
    my $self = {};
    bless $self, $class;

    $self->{'backend'} = $SPSID::Config::backend->new($options);

    return $self;
}


sub backend {return shift->{'backend'}}



sub object_exists
{
    my $self = shift;
    my $id = shift;

    return $self->backend->object_exists($id);
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
    $self->validate_object($attr);

    $self->backend->create_object($attr);

    $self->backend->log_object($id, 'Object created');

    return $id;
}



# modify or add or delete attributes of an object

sub modify_object
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;

    my $attr = $self->backend->fetch_object($id);
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

        $self->backend->delete_object_attributes($id, \@del_attrs);

        foreach my $name (@del_attrs) {

            $self->backend->log_object
                ($id,
                 'Deleted attribute: ' . $name .
                 ', value: ' . $deleted_attr->{$name});
        }
    }

    my @add_attrs = sort keys %{$added_attr};
    if( scalar(@add_attrs) > 0 ) {

        $self->backend->add_object_attributes($id, $added_attr);

        foreach my $name (@add_attrs) {

            $self->backend->log_object
                ($id,
                 'Added attribute: ' . $name .
                 ', value: ' . $added_attr->{$name});
        }
    }

    my @mod_attrs = sort keys %{$modified_attr};
    if( scalar(@mod_attrs) > 0 ) {

        $self->backend->modify_object_attributes($id, $modified_attr);

        foreach my $name (@mod_attrs) {

            $self->backend->log_object
                ($id,
                 'Modified attribute: ' . $name .
                 ', old value: ' . $old_attr->{$name} .
                 ', new value: ' . $modified_attr->{$name});
        }
    }
}




sub delete_object
{
    my $self = shift;
    my $id = shift;

    $self->backend->log_object($id, 'Object deleted');
    $self->backend->delete_object($id);
}


sub get_object
{
    my $self = shift;
    my $id = shift;

    return $self->backend->fetch_object($id);
}


# input: attribute names and values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    if( scalar(@_) == 0 ) {
        return $self->backend->contained_objects($container, $objclass);
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
                $self->backend->search_objects($container, $objclass,
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



sub validate_object
{
    my $self = shift;
    my $attr = shift;

    foreach my $func (@SPSID::Config::object_validators) {
        &{$func}($attr);
    }

    my $cfg = $SPSID::Config::object_attributes;
    $self->_verify_attributes($attr, $cfg);

    my $objclass = $attr->{'spsid.object.class'};

    if( defined($cfg->{$objclass}) ) {
        $self->_verify_attributes($attr, $cfg->{$objclass});
    }
}



sub _verify_attributes
{
    my $self = shift;
    my $attr = shift;
    my $cfg = shift;

    if( defined($cfg->{'_mandatory'}) ) {

        while( my ($name, $must) = each %{$cfg->{'_mandatory'}} ) {
            if( $must and not defined($attr->{$name}) ) {
                die('Missing mandatory attribute ' . $name . ' in ' .
                    $attr->{'spsid.object.id'});
            }
        }
    }

    if( defined($cfg->{'_unique'}) ) {

        while( my ($name, $must) = each %{$cfg->{'_unique'}} ) {

            if( defined($attr->{$name}) ) {

                my $found =
                    $self->search_objects($attr->{'spsid.object.class'},
                                          {$name => $attr->{$name}});

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
