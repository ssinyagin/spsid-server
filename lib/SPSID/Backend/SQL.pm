package SPSID::Backend::SQL;

use warnings;
use strict;

use DBI;
use Time::HiRes;

our $dbi_dsn;
our $dbi_user;
our $dbi_password;
our $dbi_attr;

my %spsid_attr_filter =
    ('spsid.object.id'    => 1, 
     'spsid.object.class' => 1,
     'spsid.object.container' => 1);

    
sub new
{
    my $class = shift;
    my $options = shift;

    if( not defined($options->{'user'}) ) {
        die('SPSID::Backend::SQL::new requires a user ID');
    }

    if( not defined($dbi_dsn) ) {
        die('$SPSID::Backend::SQL::dbi_dsn is undefined');
    }

    if( not defined($dbi_user) ) {
        die('$SPSID::Backend::SQL::dbi_user is undefined');
    }

    if( not defined($dbi_password) ) {
        die('$SPSID::Backend::SQL::dbi_password is undefined');
    }

    my $self = {};
    bless $self, $class;

    my $dbi_final_attr = {'RaiseError' => 1,
                          'AutoCommit' => 1};

    if( defined($dbi_attr) ) {
        while( my ($name, $value) = each %{$dbi_attr} ) {
            $dbi_final_attr->{$name} = $value;
        }
    }

    my $dbh = DBI->connect($dbi_dsn, $dbi_user, $dbi_password, $dbi_final_attr);
    if( not $dbh ) {
        die('Cannot connect to the database: ' . $DBI::errstr);
    }

    $self->{'dbh'} = $dbh;
    $self->{'user'} = $options->{'user'};

    return $self;
}


sub dbh {return shift->{'dbh'}}

sub DESTROY
{
    my $self = shift;
    $self->dbh->disconnect();
    return;
}


sub object_exists
{
    my $self = shift;
    my $id = shift;

    my $r = $self->dbh->selectrow_arrayref
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
    
    $self->dbh->do
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

    my $r = $self->dbh->selectrow_arrayref
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

    my $sth = $self->dbh->prepare
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
    my $msg = shift;

    my $ts = Time::HiRes::time();
    
    $self->dbh->do
        ('INSERT INTO SPSID_OBJECT_LOG ' .
         '  (OBJECT_ID, LOG_TS, MESSAGE) ' .
         'VALUES(?,?,?)',
         undef,
         $id, $ts*1000, $msg);
    
    return;
}



sub delete_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $del_attr_list = shift;

    my $sth = $self->dbh->prepare
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

    my $sth = $self->dbh->prepare
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

    my $sth = $self->dbh->prepare
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
    
    $self->dbh->do
        ('UPDATE SPSID_OBJECTS SET OBJECT_DELETED=1 WHERE OBJECT_ID=?',
         undef, $id);
    
    return;
}




sub contained_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    my $sth = $self->dbh->prepare
        ('SELECT SPSID_OBJECT_ATTR.OBJECT_ID, ATTR_NAME, ATTR_VALUE ' .
         'FROM SPSID_OBJECT_ATTR, SPSID_OBJECTS ' .
         'WHERE ' .
         ' OBJECT_CONTAINER=? AND ',
         ' OBJECT_CLASS=? AND ' .
         ' OBJECT_DELETED=0 AND ' .
         ' SPSID_OBJECT_ATTR.OBJECT_ID=SPSID_OBJECTS.OBJECT_ID');
    
    $sth->execute($container, $objclass);

    my %result;
    while( $r = $sth->fetchrow_arrayref() ) {
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
    
    my $sth = $self->dbh->prepare
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
    while( $r = $sth->fetchrow_arrayref() ) {
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





















# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:


