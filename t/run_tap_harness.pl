
use strict;
use warnings;
use TAP::Harness;


my $harness = TAP::Harness->new
    ({verbosity => 1,
      lib     => [ $ENV{'SPSID_PERLLIBDIRS'} ]});

my $testsdir = $ENV{'SPSID_TOP'} . '/t/';

local *DH;
opendir(DH, $testsdir) or die($!);

my @testfiles;

while (defined(my $file = readdir DH)) {
    if( $file =~ /\.t$/ ) {
        push(@testfiles, $testsdir . $file);
    }
}

my $aggregator = $harness->runtests(sort @testfiles);


