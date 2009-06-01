use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 9 ) ;}

require 't/common.pl';


my $ds9 = start_up();
$ds9->file( cwd . '/m31.fits.gz' );

test_stuff( $ds9, (
		   minmax =>
		   [
		    mode => 'scan',
		    mode => 'sample',
		    mode => 'datamin',
		    mode => 'irafmin',
		    [] => 'scan',
		    [] => 'sample',
		    [] => 'datamin',
		    [] => 'irafmin',
		    interval => 22,
		   ],
		  ) );

