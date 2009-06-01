use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 15 ) }

require 't/common.pl';


my $ds9 = start_up();
$ds9->file( cwd. '/m31.fits.gz' );

test_stuff( $ds9, (
		   scale =>
		   [
		    [] => 'linear',
		    [] => 'log',
		    [] => 'squared',
		    [] => 'sqrt',
		    [] => 'histequ',
		    [] => 'linear',
		    
		    datasec => 1,
		    datasec => 0,
		    
		    limits => [1, 100],
		    mode => 'minmax',
		    mode => 33,
		    mode => 'zscale',
		    mode => 'zmax',
		    
		    scope => 'global',
		    scope => 'local',
		   ],
		  ) );

