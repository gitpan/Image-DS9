use Test::More tests => 2;
use Image::DS9 qw( :all );

my $server = 'test';
my $dsp = Image::DS9->new( { Server => $server } );

unless ( $dsp->nservers )
{
  system("ds9 -title $server &");
  $dsp->wait() or die( "unable to connect to DS9\n" );
}

$dsp->scale( S_datasec, NO );

ok( '0' eq $dsp->scale( S_datasec ), 'no datasec' );

$dsp->scale( S_datasec, YES );

ok( '1' eq $dsp->scale( S_datasec ), 'datasec' );
