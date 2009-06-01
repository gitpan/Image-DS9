use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 1 ) ;}

require 't/common.pl';


my $ds9 = start_up();
$ds9->file( cwd. '/m31.fits.gz');

eval {
  $ds9->cursor( 1,1 );
};
diag $@ if $@;
ok ( ! $@, "cursor" );





