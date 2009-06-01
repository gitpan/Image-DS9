use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 7 ) ;}

require 't/common.pl';


my $ds9 = start_up();
$ds9->file( cwd . '/m31.fits.gz' );

test_stuff( $ds9, (
		   mode =>
		   [
		    [] => 'crosshair',
		    [] => 'colorbar',
		    [] => 'pan',
		    [] => 'zoom',
		    [] => 'rotate',
		    [] => 'examine',
		    [] => 'pointer',
		   ],
		  ) );

