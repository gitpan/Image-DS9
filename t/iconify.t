use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 2 ) ;}

require 't/common.pl';


my $ds9 = start_up();

test_stuff( $ds9, (
		   iconify =>
		   [
		    [] => 1,
		    [] => 0,
		   ],
		  ) );

