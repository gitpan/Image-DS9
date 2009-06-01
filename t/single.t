use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 3 ) ;}

require 't/common.pl';


my $ds9 = start_up();
load_events( $ds9 );
$ds9->file( cwd. '/m31.fits.gz', { new => 1 } );

$ds9->single();
ok( 1 == $ds9->single('state'), "single" );
ok( 0 == $ds9->blink('state'), "single; blink off");
ok( 0 == $ds9->tile('state'), "single; tile off");


