package SPSID::Backend::SQL;

use warnings;
use strict;

use DBI;

our $dbi_dsn;
our $dbi_user;
our $dbi_password;
our $dbi_attr;

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


sub DESTROY
{
    my $self = shift;
    $self->{'dbh'}->disconnect();
}


sub object_exists
{
    my $self = shift;
    my $id = shift;
}


sub create_object
{
    my $self = shift;
    my $attr = shift;
}


sub fetch_object
{
    my $self = shift;
    my $id = shift;
}


sub log_object
{
    my $self = shift;
    my $id = shift;
    my $msg = shift;
}


sub delete_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $del_attr_list = shift;
}

sub add_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $add_attr = shift;
}

sub modify_object_attributes
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;
}


sub delete_object
{
    my $self = shift;
    my $id = shift;
}


# input: attribute values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $objclass = shift;
    my $attr = shift;

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


