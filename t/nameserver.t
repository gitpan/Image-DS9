use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;

BEGIN { plan( tests => 6 ) ;}

require 't/common.pl';


my $ds9 = start_up();

test_stuff( $ds9, (
		   nameserver =>
		   [
		    server => 'ned-sao',
		    server => 'ned-eso',
		    server => 'simbad-sao',
		    server => 'simbad-eso',
		    skyformat => 'degrees',
		   ],
		  ) );


SKIP: {
      skip '5.6.3 returns incorrect value for skyformat if it is sexagesimal', 1 if $ds9->version eq '5.6.3';

test_stuff( $ds9, (
		   nameserver =>
		   [
		    skyformat => 'sexagesimal',
		   ],
		  ) );
}

