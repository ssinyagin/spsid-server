package SPSID::Backend::SQL;

use DBI;
use Time::HiRes;
use Moose;



has 'dbi_dsn' =>
    (
     is  => 'ro',
     isa => 'Str',
     default => $SPSID::Config::Backend::SQL::dbi_dsn,
     required => 1,
    );

has 'dbi_user' =>
    (
     is  => 'ro',
     isa => 'Str',
     default => $SPSID::Config::Backend::SQL::dbi_user,
     required => 1,
    );


has 'dbi_password' =>
    (
     is  => 'ro',
     isa => 'Str',
     default => $SPSID::Config::Backend::SQL::dbi_password,
     required => 1,
    );


has 'dbi_attr' =>
    (
     is  => 'ro',
     isa => 'HashRef',
     default => sub { defined($SPSID::Config::Backend::SQL::dbi_attr) ?
                          $SPSID::Config::Backend::SQL::dbi_attr : {}},
    );


has '_dbh' =>
    (
     is  => 'rw',
     isa => 'Object',
     init_arg => undef,
     handles => {disconnect => 'disconnect'},
    );




my %spsid_attr_filter =
    ('spsid.object.id'    => 1,
     'spsid.object.class' => 1,
     'spsid.object.container' => 1);



sub connect
{
    my $self = shift;

    my $dbi_final_attr = {'RaiseError' => 1,
                          'AutoCommit' => 1};

    my $dbi_attr = $self->dbi_attr;

    if( defined($dbi_attr) ) {
        while( my ($name, $value) = each %{$dbi_attr} ) {
            $dbi_final_attr->{$name} = $value;
        }
    }

    my $dbh = DBI->connect($self->dbi_dsn,
                           $self->dbi_user,
                           $self->dbi_password,
                           $dbi_final_attr);
    if( not $dbh ) {
        die('Cannot connect to the database: ' . $DBI::errstr);
    }

    $self->_dbh($dbh);
    return;
}



sub DEMOLISH
{
    my $self = shift;
    $self->disconnect();
    return;
}


sub object_exists
{
    my $self = shift;
    my $id = shift;

    my $r = $self->_dbh->selectrow_arrayref
        ('SELECT OBJECT_ID FROM SPSID_OBJECTS WHERE OBJECT_ID=? ' .
         'AND OBJECT_DELETED=0',
         undef, $id);

    return (defined($r)? 1:0);
}


sub create_object
{
    my $self = shift;
    my $attr = shift;

    my $id = $attr->{'spsid.object.id'};

    $self->_dbh->do
        ('INSERT INTO SPSID_OBJECTS ' .
         '  (OBJECT_ID, OBJECT_CLASS, OBJECT_CONTAINER) ' .
         'VALUES(?,?,?)',
         undef,
         $id,
         $attr->{'spsid.object.class'},
         $attr->{'spsid.object.container'});

    $self->add_object_attributes($id, $attr);

    return;
}


sub fetch_object
{
    my $self = shift;
    my $id = shift;

    my $r = $self->_dbh->selectrow_arrayref
        ('SELECT OBJECT_DELETED, OBJECT_CLASS, OBJECT_CONTAINER ' .
         'FROM SPSID_OBJECTS WHERE OBJECT_ID=?',
         undef, $id);

    if( not defined($r) ) {
        die('Object does not exist: ' . $id);
    }
    elsif( not $r->[0] ) {
        die('Object is deleted: ' . $id);
    }

    my $attr = {'spsid.object.id'        => $id,
                'spsid.object.class'     => $r->[1],
                'spsid.object.container' => $r->[2]};

    my $sth = $self->_dbh->prepare
        ('SELECT ATTR_NAME, ATTR_VALUE FROM SPSID_OBJECT_ATTR ' .
         'WHERE OBJECT_ID=?');
    $sth->execute($id);

    while( $r = $sth->fetchrow_arrayref() ) {
        $attr->{$r->[0]} = $r->[1];
    }

    return $attr;
}



sub log_object
{
    my $self = shift;
    my $id = shift;
    my $user_id = shift;
    my $msg = shift;

    my $ts = Time::HiRes::time();

    $self->_dbh->do
        ('INSERT INTO SPSID_OBJECT_LOG ' .
         '  (OBJECT_ID, LOG_TS, USER_ID, MESSAGE) ' .
         'VALUES(?,?,?,?)',
         undef,
         $id, $ts*1000, $user_id, $msg);

    return;
}



sub delete_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $del_attr_list = shift;

    my $sth = $self->_dbh->prepare
        ('DELETE FROM SPSID_OBJECT_ATTR ' .
         'WHERE OBJECT_ID=? AND ATTR_NAME=?');

    foreach my $name (@{$del_attr_list}) {
        $sth->execute($id, $name);
    }

    return;
}



sub add_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $add_attr = shift;

    my $sth = $self->_dbh->prepare
        ('INSERT INTO SPSID_OBJECT_ATTR ' .
         '  (OBJECT_ID, ATTR_NAME, ATTR_VALUE) ' .
         'VALUES(?,?,?)');

    while( my ($name, $value) = each %{$add_attr} ) {
        if( not $spsid_attr_filter{$name} ) {
            $sth->execute($id, $name, $value);
        }
    }

    return;
}



sub modify_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;

    my $sth = $self->_dbh->prepare
        ('UPDATE SPSID_OBJECT_ATTR ' .
         '  SET ATTR_VALUE=? WHERE OBJECT_ID=? AND ATTR_NAME=?');

    while( my ($name, $value) = each %{$mod_attr} ) {
        if( not $spsid_attr_filter{$name} ) {
            $sth->execute($value, $id, $name);
        }
    }

    return;
}



sub delete_object
{
    my $self = shift;
    my $id = shift;

    if( $self->object_exists($id) ) {
        die('Trying to delete the opbect twice: ' . $id);
    }

    $self->_dbh->do
        ('UPDATE SPSID_OBJECTS SET OBJECT_DELETED=1 WHERE OBJECT_ID=?',
         undef, $id);

    return;
}




sub contained_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    my $sth = $self->_dbh->prepare
        ('SELECT SPSID_OBJECT_ATTR.OBJECT_ID, ATTR_NAME, ATTR_VALUE ' .
         'FROM SPSID_OBJECT_ATTR, SPSID_OBJECTS ' .
         'WHERE ' .
         ' OBJECT_CONTAINER=? AND ',
         ' OBJECT_CLASS=? AND ' .
         ' OBJECT_DELETED=0 AND ' .
         ' SPSID_OBJECT_ATTR.OBJECT_ID=SPSID_OBJECTS.OBJECT_ID');

    $sth->execute($container, $objclass);

    my %result;
    while( my $r = $sth->fetchrow_arrayref() ) {
        $result{$r->[0]}{$r->[1]} = $r->[2];
    }

    my $ret = [];

    while( my ($id, $attr) = each %result ) {
        $attr->{'spsid.object.id'} = $id;
        $attr->{'spsid.object.class'} = $objclass;
        $attr->{'spsid.object.container'} = $container;

        push(@{$ret}, $attr);
    }

    return $ret;
}


# input: attribute value for searching
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;
    my $attr_name = shift;
    my $attr_value = shift;

    my $sth = $self->_dbh->prepare
        ('SELECT OBJECT_ID, ATTR_NAME, ATTR_VALUE ' .
         'FROM SPSID_OBJECT_ATTR ' .
         'WHERE OBJECT_ID IN (' .
         '  SELECT SPSID_OBJECT_ATTR.OBJECT_ID ' .
         '  FROM SPSID_OBJECT_ATTR, SPSID_OBJECTS ' .
         '  WHERE ' .
         '   OBJECT_CONTAINER=? AND ',
         '   OBJECT_CLASS=? AND ' .
         '   OBJECT_DELETED=0 AND ' .
         '   SPSID_OBJECT_ATTR.OBJECT_ID=SPSID_OBJECTS.OBJECT_ID AND ' .
         '   ATTR_NAME=? ' .
         '   ATTR_VALUE=?)');

    $sth->execute($container, $objclass, $attr_name, $attr_value);

    my %result;
    while( my $r = $sth->fetchrow_arrayref() ) {
        $result{$r->[0]}{$r->[1]} = $r->[2];
    }

    my $ret = [];

    while( my ($id, $attr) = each %result ) {
        $attr->{'spsid.object.id'} = $id;
        $attr->{'spsid.object.class'} = $objclass;
        $attr->{'spsid.object.container'} = $container;

        push(@{$ret}, $attr);
    }

    return $ret;
}



sub contained_classes
{
    my $self = shift;
    my $container = shift;

    my $sth = $self->_dbh->prepare
        ('SELECT DISTINCT OBJECT_CLASS ' .
         'FROM SPSID_OBJECTS ' .
         'WHERE OBJECT_CONTAINER=?');

    $sth->execute($container);

    my $ret = [];
    while( my $r = $sth->fetchrow_arrayref() ) {
        push(@{$ret}, $r->[0]);
    }
    
    return $ret;
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


