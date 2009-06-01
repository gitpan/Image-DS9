use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 1 ) }

require 't/common.pl';

my $ds9 = start_up();
$ds9->file( cwd. '/m31.fits.gz' );

my @coords = qw( 00:42:41.377 +41:15:24.28 );
$ds9->pan( to => @coords, qw( wcs fk5) );
ok( eq_array( \@coords, 
	      scalar $ds9->pan(qw( wcs fk5 sexagesimal ))), 
    'pan' );
