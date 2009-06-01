use strict;
use warnings;

use Test::More;
use Image::DS9;
use Cwd;
use File::stat;

BEGIN { plan( tests => 2 ) ;}

require 't/common.pl';


my $ds9 = start_up();
load_events( $ds9 );

our $imgfile = "snooker.img.fits.gz";

unlink $imgfile;
eval { 
  my $fitsimg = $ds9->fits( 'image', 'gz' );
  open ( FITS, ">$imgfile" ) or die( "unable to create $imgfile\n" );
  syswrite FITS, $$fitsimg;
  close FITS;
};

diag $@ if $@;
ok( !$@, "fits image gz get" );

eval {
  my $sb = stat( $imgfile ) or die( "unable to stat $imgfile" );
  open( FILE, $imgfile ) or die( "unable to open $imgfile" );
  my $fitsimg;
  sysread FILE, $fitsimg, $sb->size;
  close FILE;
  $ds9->fits( $fitsimg, { new => 1 } );
};
diag $@ if $@;
ok( !$@, "fits image gz set" );

unlink $imgfile;
