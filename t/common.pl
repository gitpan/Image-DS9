use Image::DS9;

our $verbose = 0;

sub start_up
{

  my $ds9 = Image::DS9->new( { Server => 'ImageDS9', verbose => $verbose });
  unless ( $ds9->nservers )
  {
    system( "ds9 -title ImageDS9 &" );
    $ds9->wait() or die( "unable to connect to DS9\n" );
  }
  
  $ds9->raise();
  $ds9;
}

sub clear
{
  my $ds9 = shift;

  $ds9->frame( delete => 'all' );
  $ds9->frame( 'new' );
}


# need this to get around bugs in ds9
sub load_events
{
  my $ds9 = shift;

  eval {
    $ds9->file( cwd() . "/snooker.fits.gz", { extname => 'raytrace', 
					   bin => [ 'rt_x', 'rt_y' ] } );
  };
  $ds9->bin( factor => 0.025 );
  $ds9->zoom( 0 );
}

sub test_stuff
{
  my ( $ds9, @stuff ) = @_;


  while ( my ( $cmd, $subcmds ) = splice( @stuff, 0, 2 ) )
  {
    last if $cmd eq 'stop';

    while ( my ( $subcmd, $args ) = splice( @$subcmds, 0, 2 ) )
    {
      my @subcmd = ( 'ARRAY' eq ref $subcmd ? @$subcmd : $subcmd );
      $subcmd = join( ' ', @$subcmd) if 'ARRAY' eq ref $subcmd;

      $args = [ $args ] unless 'ARRAY' eq ref $args;

      my $ret;
      eval {
	$ds9->$cmd(@subcmd, @$args);
	$ret = $ds9->$cmd(@subcmd);
      };

      print($@) && fail( "$cmd $subcmd" ) if $@;

      if ( ! ref($ret) && 1 == @$args )
      {
	ok( $ret eq $args->[0], "$cmd $subcmd" );
      }
      elsif ( @$ret == @$args )
      {
	ok ( eq_array( $ret, $args ), "$cmd $subcmd" );
      }
      else
      {
	fail( "$cmd $subcmd" );
      }
    }
  }

}


1;
