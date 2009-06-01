use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 1 ) ;}

require 't/common.pl';


my $ds9 = start_up();
load_events( $ds9 );
ok( cwd() . "/snooker.fits.gz[RAYTRACE]" eq $ds9->file(), 
    "file name retrieval" );
