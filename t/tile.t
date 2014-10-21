use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 9 ) ;}

require 't/common.pl';


my $ds9 = start_up();
$ds9->file( cwd. '/m31.fits.gz' );
$ds9->file( cwd. '/m31.fits.gz', { new => 1 } );

test_stuff( $ds9, (
		   tile =>
		   [
		    [] => 1,
		    mode => 'column',
		    mode => 'row',
		    mode => 'grid',
		    [qw( grid mode )] => 'manual',
		    [qw( grid mode )] => 'automatic',
		    [qw( grid layout )] => [5,5],
		    [qw( grid gap )] => 3,
		    [] => 0,
		   ],
		  ) );

