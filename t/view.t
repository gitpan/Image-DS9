use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 72 ) ;}

require 't/common.pl';


my $ds9 = start_up();

test_stuff( $ds9, (
		   view =>
		   [
		    ( map { $_ => 0, $_ => 1 } 
		      qw( info panner magnifier buttons colorbar 
			  image physical wcs ),
		    ),
		    ( map { $_ => 1, $_ => 0 } 
		      ( qw( horzgraph vertgraph ), 
			map { 'wcs' . $_ } ('a'..'z') )
		    ),
		   ]
		  ) );

