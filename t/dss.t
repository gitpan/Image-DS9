use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 7 ) ;}

require 't/common.pl';


my $ds9 = start_up();

test_stuff( $ds9, (
		   dsssao =>
		   [
		    size => [10,10],
		    name => 'NGC5846'
		   ],

		   dsseso =>
		   [
		    size => [10,10],
		    name => 'NGC5846',
		   ],

		   dssstsci =>
		   [
		    size => [10,10],
		    survey => 'all',
		    name => 'NGC5846',
		   ]
		  ) );

