use Test::More tests => 6;
use Image::DS9 qw( :all );

my $server = 'test';
my $dsp = Image::DS9->new( { Server => $server } );

unless ( $dsp->nservers )
{
  system("ds9 -title $server &");
  $dsp->wait() or die( "unable to connect to DS9\n" );
}

$dsp->frame( delete => FR_all );

ok( '' eq $dsp->frame(), 'no frames' );

$dsp->frame( FR_new );

ok( '1' eq $dsp->frame(), 'one frame' );
  
$dsp->frame( FR_new );

ok( '2' eq $dsp->frame(), 'two frame' );

$dsp->frame( hide => FR_all );

ok( '' eq $dsp->frame(), 'hide frames' );

$dsp->frame( 2 );

ok( '2' eq $dsp->frame(), 'goto frame' );

my $frames = $dsp->frame( FR_all );

ok( eq_array( $frames, [ 1, 2] ), "frame list" );
