use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { 
      plan( tests => 2 ); }

require 't/common.pl';

my $ds9 = start_up();
$ds9->file( cwd. '/m31.fits.gz' );

$ds9->crosshair( 0, 0, 'image' );
ok( eq_array( scalar $ds9->crosshair( 'image' ), [0,0]), 'crosshair' );

my @coords = qw( 00:42:41.399 +41:15:23.78 );
$ds9->crosshair( @coords, wcs => 'fk5');
ok( eq_array( \@coords, 
	      scalar $ds9->crosshair(qw( wcs fk5 sexagesimal ))), 
    'crosshair' );
