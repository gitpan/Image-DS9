use Test::More tests => 7;
use Image::DS9 qw( :all );

my $server = 'test';
my $dsp = Image::DS9->new( { Server => $server } );

unless ( $dsp->nservers )
{
  system("ds9 -title $server &");
  $dsp->wait() or die( "unable to connect to DS9\n" );
}

$dsp->tile_mode( T_grid );

ok( T_grid eq $dsp->tile_mode(), 'grid' );

$dsp->tile_mode( T_column );

ok( T_column eq $dsp->tile_mode(), 'column' );

$dsp->tile_mode( T_row );

ok( T_row eq $dsp->tile_mode(), 'row' );

$dsp->tile_mode( T_grid, T_gap, 30 );

ok( 30 eq $dsp->tile_mode( T_grid, T_gap ), 'grid gap' );

$dsp->tile_mode( T_grid, T_mode, T_auto );

ok( T_auto eq $dsp->tile_mode( T_grid, T_mode ), 'grid mode' );

$dsp->tile_mode( T_grid, T_mode, T_manual );

ok( T_manual eq $dsp->tile_mode( T_grid, T_mode ), 'grid mode' );

$dsp->tile_mode( T_grid, T_layout, 5, 5 );

ok( eq_array( [5,5], scalar $dsp->tile_mode( T_grid, T_layout ) ), 
    'grid layout' );
