package Image::DS9;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $use_PDL);


BEGIN {
  eval "use PDL::Types; use PDL::Core"; 
  $use_PDL = $@ ? 0 : 1;
}


require Exporter;

@ISA = qw( Exporter );

@EXPORT = qw( );

my @frame_ops = qw( 
		   FR_center
		   FR_clear
		   FR_delete
		   FR_hide
		   FR_new
		   FR_refresh
		   FR_reset
		   FR_first
		   FR_next
		   FR_prev
		   FR_last
		  );

my @display_ops = qw( D_blink D_tile D_single );

my @tile_ops  = qw( T_Grid T_Column T_Row );

my @extra_ops = qw( ON OFF YES NO );

my @filetype_ops = qw( FT_MosaicImage FT_MosaicImages FT_Mosaic FT_Array );

my @scale_ops = qw( S_linear S_ln S_log S_squared 
		    S_sqrt S_minmax S_zscale S_user S_local S_global );


@EXPORT_OK = ( @frame_ops, @tile_ops, @extra_ops, @filetype_ops, 
	       @display_ops, @scale_ops );

%EXPORT_TAGS = ( 
		frame => \@frame_ops,
		tile => \@tile_ops,
		filetype => \@filetype_ops,
		display => \@display_ops,
		scale => \@scale_ops,
		all => [ @EXPORT_OK ],
	       );
$VERSION = '0.07';

use Carp;
use Data::Dumper;
use IPC::XPA;
use constant SERVER => 'ds9';
use constant CLASS => 'Image::DS9';


use constant ON		=> 1;
use constant OFF	=> 0;
use constant YES	=> 'yes';
use constant NO		=> 'no';


# Preloaded methods go here.

sub _flatten_hash
{
  my ( $hash ) = @_;

  return '' unless keys %$hash;

  join( ',', map { "$_=" . $hash->{$_} } keys %$hash );
}

# create new XPA object
{

  my %def_obj_attrs = ( Server => SERVER, min_servers => 1 );
  my %def_xpa_attrs = ( max_servers => 1 );

  sub new
  {
    my ( $class, $u_attrs ) = @_;
    $class = ref($class) || $class;
    
    # load up attributes, first from defaults, then
    # from user.  ignore bogus elements in user attributes hash

    my $self = bless { 
		      xpa => IPC::XPA->Open, 
		      %def_obj_attrs,
		      xpa_attrs => { %def_xpa_attrs},
		      res => undef
		     }, $class;
    
    croak( CLASS, "->new -- error creating XPA object" )
      unless defined $self->{xpa};

    
    $self->{xpa_attrs}{max_servers} = $self->nservers || 1;

    $self->set_attrs($u_attrs);

    $self;
  }

  sub set_attrs
  {
    my $self = shift;
    my $u_attrs = shift;

    return unless $u_attrs;
    $self->{xpa_attrs}{$_} = $u_attrs->{$_}
      foreach grep { exists $def_xpa_attrs{$_} } keys %$u_attrs;
    
    $self->{$_} = $u_attrs->{$_} 
      foreach grep { exists $def_obj_attrs{$_} } keys %$u_attrs;
  }

}

sub nservers
{
  my $self = shift;

  $self->{xpa}->Access( $self->{Server}, 'gs' );
}

sub res
{
  my $self = shift;

  $self->{res};
}

{
  # mapping between PDL
  my %map;

  if ( $use_PDL )
  {
    %map = (
	    $PDL::Types::PDL_B => 8,
	    $PDL::Types::PDL_S => 16,
	    $PDL::Types::PDL_S => 16,
	    $PDL::Types::PDL_L => 32,
	    $PDL::Types::PDL_F => -32,
	    $PDL::Types::PDL_D => -64
	   );
  }

  my %def_attrs = ( xdim => undef,
		    ydim => undef,
		    bitpix => undef );
  
  sub array
  {
    my ( $self, $image, $attrs ) = @_;
    
    my %attrs = ( $attrs ? %$attrs : () );

    my $data = $image;

    if ( $use_PDL && 'PDL' eq ref( $image ) )
    {
      $attrs{bitpix} = $map{$image->get_datatype};
      ($attrs{xdim}, $attrs{ydim}) = $image->dims;
      $data = ${$image->get_dataref};
    }
    
    if ( exists $attrs{dim} )
    {
      delete $attrs{xdim};
      delete $attrs{ydim};
    }

    my @notset = grep { ! defined $attrs{$_} } keys %attrs;
    croak( CLASS, '->array -- the following attributes were not defined: ',
	   join( ',', map { "'$_'" } @notset) )
      if @notset;

    $self->Set( 'array ['._flatten_hash(\%attrs).']', $data );
  }
}

use constant D_tile   => 'tile';
use constant D_single => 'single';
use constant D_blink  => 'blink';

sub display
{
  my ( $self, $state ) = @_;

  croak( CLASS, '->display -- unknown display type' )
    if $state ne D_blink && $state ne D_tile && $state ne D_single;

  $self->Set( $state );
}

use constant T_Grid	 => 'grid';
use constant T_Column	 => 'column';
use constant T_Row	 => 'row';

sub tile_mode
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return $self->Get( 'tile mode' );
  }

  else
  {
    $self->Set( "tile mode $state" );
  }

}

sub colormap
{
  my ( $self, $colormap ) = @_;

  unless ( defined $colormap )
  {
    return $self->Get( 'colormap' );
  }

  else
  {
    $self->Set( "colormap $colormap" );
  }
}

use constant FR_center  => 'center';
use constant FR_clear	 => 'clear';
use constant FR_delete  => 'delete';
use constant FR_hide    => 'hide';
use constant FR_new     => 'new';
use constant FR_refresh => 'refresh';
use constant FR_reset   => 'reset';
use constant FR_first	 => 'first';
use constant FR_next	 => 'next';
use constant FR_prev	 => 'prev';
use constant FR_last	 => 'last';

sub frame
{
  my $self = shift;
  my $cmd = shift;

  unless( defined $cmd )
  {
    return $self->Get( 'frame' );
  }

  elsif ( 'show' eq $cmd )
  {
    my $frame = shift;
    $self->Set( "frame show $frame" );
  }

  else
  {
    croak( CLASS, '->frame -- too many arguments' )
      if @_;
    $self->Set( "frame $cmd" );
  }


}

use constant FT_MosaicImage	=> 'mosaicimage';
use constant FT_MosaicImages	=> 'mosaicimages';
use constant FT_Mosaic		=> 'mosaic';
use constant FT_Array		=> 'array';

sub file
{
  my ( $self, $file, $type ) = @_;

  unless( defined $file )
  {
    return $self->Get( 'file' );
  }

  else
  {
    $type ||= '';
    $self->Set( "file $type $file" );
  }


}

use constant S_linear	=> 'linear';
use constant S_ln	=> 'ln';
use constant S_log	=> 'log';
use constant S_squared	=> 'squared';
use constant S_sqrt	=> 'sqrt';
use constant S_minmax	=> 'minmax';
use constant S_zscale	=> 'zscale';
use constant S_user	=> 'user';
use constant S_local	=> 'local';
use constant S_global	=> 'global';

my @scale_scopes = ( S_local, S_global );
my @scale_modes = ( S_minmax, S_zscale, S_user );
my @scale_algs = ( S_linear, S_ln, S_log, S_squared, S_sqrt );

sub scale
{
  my $self = shift;
  my $what = shift;

  if ( 'scope' eq $what )
  {
    my $scope = shift;
    grep { $_ eq $scope } @scale_scopes
      or croak( "unknown scale scope value" );

    $self->Set( "scale scope $scope" );
  }
  elsif ( 'limits' eq $what )
  {
    my $minmax = shift;
    croak ( 'expected array ref for scale limit value' )
      unless 'ARRAY' eq ref($minmax);
    croak ( 'not enough values for scale limits' )
      unless $#{$minmax} >= 2;

    $self->Set( "scale limits $minmax->[0] $minmax->[1]" );
  }
  elsif( 'mode' eq $what )
  {
    my $mode = shift;
    grep { $_ eq $mode } @scale_modes
      or croak( "unknown scale mode value" );

    $self->Set( "scale mode $mode" );
  }
  else
  {
    grep { $_ eq $what } @scale_algs
      or croak( "unknown scale algorithm" );
    $self->Set( "scale $what" );
  }
}

sub zoom
{
  my $self = shift;
  my $what = shift;

  if ( 'abs' eq $what )
  {
    $self->Set( "zoom to $what" );
  }
  elsif ( 'rel' eq $what )
  {
    $self->Set( "zoom $what" );
  }
  elsif ( 0 == $what )
  {
    $self->Set( "zoom to fit" );
  }
  else
  {
    $self->Set( "zoom to $what" );
  }
}

sub Set
{
  my ( $self, $cmd, $buf ) = @_;

  $self->{res} = [
    $self->{xpa}->Set( $self->{Server}, $cmd, $buf, $self->{xpa_attrs} ) ];
  if ( grep { defined $_->{message} } @{$self->{res}} )
  {
    croak( CLASS, " -- error sending data to server" );
  }

  croak( CLASS, " -- fewer than ",$self->{min_servers}," server(s) responded" )
    if @{$self->{res}} < $self->{min_servers};
}

sub Get
{
  my ( $self, $cmd ) = @_;
  my @res = $self->{xpa}->Get( $self->{Server}, $cmd, $self->{xpa_attrs} );
  if ( grep { defined $_->{message} } @res )
  {
    $self->{res} = \@res;
    croak( CLASS, " -- error sending data to server" );
  }
  
  croak( CLASS, " -- fewer than ",$self->{min_servers}," servers(s) responded" )
    if @res < $self->{min_servers};

  if ( 1 == $self->{xpa_attrs}{max_servers} )
  {
    chomp $res[0]->{buf};
    return $res[0]->{buf};
  }
  else
  {
    return map { chomp $_->{buf}; 
	         { name => $_->{name}, buf => $_->{buf} } } @res;
  }
}



# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Image::DS9 - interface to the DS9 image display and analysis program

=head1 SYNOPSIS

  use Image::DS9;
  use Image::DS9 qw( :frame :tile :filetype );
  use Image::DS9 qw( :all );

  $dsp = new Image::DS9;
  $dsp = new Image::DS9( \%attrs );

  $nservers = $dsp->nservers;

  $dsp->array( $image );
  $dsp->array( $image, \%attrs );

  $dsp->blink( $state );

  $dsp->colormap( $colormap );
  @colormaps = $dsp->colormap;

  $dsp->frame( $frame_op );
  @frames = $dsp->frame;

  $last_results = $dsp->res;

=head1 DESCRIPTION

This class provides access to the B<DS9> image display and analysis
program through its B<XPA> access points.

B<DS9> is a rather flexible and feature-rich image display program.
Rather than extol its virtues, please consult the website in
L</REQUIREMENTS>.

This class is rather bare at present, providing a low level
interface to the XPA access points.  Eventually these will be
hidden by an elegant framework that will make life wonderful.

To use this class, first construct a B<Image::DS9> object, and
then apply it's methods.  It is possible to both address more
than one B<DS9> with a single object, as well as having
multiple B<Image::DS9> objects communicate with their own
B<DS9> invocations.  Eventually there will be documentation
spelling out how to do this.


=head1 METHODS

=head2 Constants

Predefined constants may be imported when the B<Image::DS9> package
is loaded, by specifying one or more of the following tags:
C<frame>, C<tile>, C<filetype>, C<all>.  For example:

	use Image::DS9 qw( :frame :tile :filetype :display );

The C<frame> group imports
C<FR_center>,
C<FR_clear>,
C<FR_delete>,
C<FR_hide>,
C<FR_new>,
C<FR_refresh>,
C<FR_reset>,
C<FR_first>,
C<FR_next>,
C<FR_prev>,
C<FR_last>.

The C<tile> group imports
C<T_Grid>,
C<T_Column>,
C<T_Row>.

The C<filetype> group imports
C<FT_MosaicImage>,
C<FT_MosaicImages>,
C<FT_Mosaic>,
C<FT_Array>.

The C<display> group imports
C<D_blink>,
C<D_tile>,
C<D_single>.

The C<scale> group imports
C<S_linear>,
C<S_ln>,
C<S_log>,
C<S_squared>,
C<S_sqrt>,
C<S_minmax>,
C<S_zscale>,
C<S_user>,
C<S_local>,
C<S_global>.


The C<all> group imports all of the above groups, as well as
C<ON>,
C<OFF>,
C<YES>
C<NO>.


=head2 Return values

Because a single B<Image::DS9> object may communicate with multiple
instances of B<DS9>, most return values are lists, rather than scalars.
These are lists of hashes, with keys C<name> and C<buf>.  For example,

	use Data::Dumper;
	@colormaps = $dsp->colormap;
	print Dumper \@colormaps;

yields

	$VAR1 = [
	          {
	            'name' => 'DS9:ds9 838e2ab4:32832',
	            'buf' => 'Grey
	'
	          }
	        ];

Note the end of line character in the colormap name.

B<However>, if the object was created with B<max_servers> set to 1,
it returns the contents of C<buf> directly, i.e.

	$colormap = $dsp->colormap;

=head2 Error Returns

In case of error, an exception is thrown, and the results
from the XPA call which failed are made available via the B<res>
method.

=head2 Methods

=over 8

=item new

  $dsp = new Image::DS9;
  $dsp = new Image::DS9( \%attrs );

Construct a new object.  It returns a handle to the object.  It throws
an exception (catch via B<eval>) upon error.

The optional hash B<attrs> may contain one of the following keys:

=over 8

=item Server

An alternate server to which to communicate.  It defaults to C<ds9>.

=item max_servers

The maximum number of servers to which to communicate.  It defaults to
the number of C<DS9> servers running at the time the constructor is
called.

=item min_servers

The minimum number of servers which should respond to commands.  If
a response is not received from at least this many servers, an exception
will be thrown.  It defaults to C<1>.


=back

For example,

	$dsp = new Image::DS9( { max_servers => 3 } );


=item nservers

  $nservers = $dsp->nservers;

This returns the number of servers which the object is communicating
with.

=item array

  $dsp->array( $image );
  $dsp->array( $image, \%attrs );

This is a simple interface to the B<array> access point, which displays
images.  If B<$image> is a PDL object, all required information is
extracted from it, and it is passed to B<DS9>.  Otherwise, it should
be binary data suitable for B<DS9>, and the B<attrs> hash should be
used to pass dimensional and size data to B<DS9>.  B<attrs> may
contain the following elements:

=over 8

=item xdim

The X coordinate array extent.

=item ydim

The Y coordinate array extent.

=item bitpix

The number of bits per pixel.  Negative values indicate a floating point
number.

=back

=item display

  $dsp->display( $state );

Change how frames are displayed.  C<$state> may be one of the constants
C<D_blink>, C<D_tile>, or C<D_single> (or, equivalently, 
'blink', 'tile', 'single' ).  The constants are available
by importing the C<display> tag.

=item file

  $dsp->file( $file );
  $dsp->file( $file, $type );

Display the specified C<$file>.  The file type is optional, and may be
one of the following constants: C<FT_MosaicImage>, C<FT_MosaicImages>,
C<FT_Mosaic>, C<FT_Array> (or one of the strings C<'mosaicimage'>,
C<'mosaicimages'>, C<'mosaic'>, or C<'array'> ). (Import the C<filetype>
tag to get the constants).

If called without a value, it will return the current file name loaded
for the curent frame.

=item tile_mode

  $dsp->tile_mode( $mode );

The tiling mode may be specified by setting C<$mode> to C<T_Grid>,
C<T_Column>, or C<T_Row>.  These constants are available if the
C<tile_op> tags are imported.  Otherwise, use C<'grid'>, c<'column'>,
or C<'row'>.  If called without a value, it will return the
current tiling mode.


=item colormap

  $dsp->colormap( $colormap );
  @colormaps = $dsp->colormap;

If an argument is specified, it should be the name of a colormap (case
is not important).  If no arguments are specified, the current colormaps
for all of the B<DS9> instances is returned, as a list containing
references to hashes with the keys C<name> and C<buf>.  The latter
will contain the colormap name.


=item frame

  $dsp->frame( $frame_op );
  $dsp->frame( show => $frame );
  @frames = $dsp->frame;

Command B<DS9> to do frame operations.  Frame operations are nominally
strings.  As B<DS9> will interpret any string which isn't a frame operation
as the name of frame to switch to (or create, if necessary), B<Image::DS9>
provides constants for the standard operations to prevent typos.  See
the L<Constants> section.
Otherwise, use the strings 
C<center>,
C<clear>,
C<delete>,
C<hide>,
C<new>,
C<refresh>,
C<reset>,
C<first>,
C<next>,
C<prev>,
C<last>.

To load a particular frame, specify the frame name as the operator.

To show a frame which has been hidden, use the second form with
the C<show> operator.

For example,

	$dsp->frame( FR_new );		# use the constant
	$dsp->frame( 'new' );		# use the string literal
	$dsp->frame( '3' );		# load frame 3
	$dsp->frame( FR_hide );		# hide the current frame
	$dsp->frame( show => 3 );	# show frame 3
	$dsp->frame( FR_delete );	# delete the current frame

If B<frame()> is called with no arguments, it returns a list of the
current frames for all instances of B<DS9>.

=item res

  $res = $dsp->res;

In case of error, the returned results from the failing B<XPA> call
are available via this method.  It returns a reference to an
array of hashes, one per instance of B<DS9> addressed by the object.
See the B<IPC::XPA> documentation for more information on what
the hashes contain.


=item scale

  $dsp->scale( $algorithm );
  $dsp->scale( limits => [ $min, $max ] );
  $dsp->scale( mode => $mode );
  $dsp->scale( scope => $scope );

This specifies how the data will be scaled.  C<$algorithm> may
be one of the constants 
C<S_linear>,
C<S_ln>,
C<S_log>,
C<S_squared>,
C<S_sqrt>
(or, equivalently, 
C<'linear'>,
C<'ln'>,
C<'log'>,
C<'squared'>,
C<'sqrt'>).

C<$mode> may be one of 
C<S_minmax>,
C<S_zscale>,
C<S_user>
(or, equivalently,
C<'minmax'>,
C<'zscale'>,
C<'user'>).

C<$scope> may be on of
C<S_local>,
C<S_global>
(or, equivalently,
C<'local'>,
C<'global'>
).

The constants are available if the C<scale> tag is imported.

=item zoom

  $dsp->zoom( abs => $zoom );
  $dsp->zoom( rel => $zoom );
  $dsp->zoom( $zoom );

This changes the zoom value for the current frame.  C<$zoom> is a
positive numerical value.  A zoom value may be absolute or relative.
This is explicitly specified in the second and third forms of the
method invocation.  If not specified (as in the third form)
it is absolute.  To zoom such that the image fits with in the frame,
specify a zoom value of C<0>.


=back


=head1 REQUIREMENTS

B<Image::DS9> requires B<IPC::XPA> to be installed.  At present, both
B<DS9> and B<xpans> (part of the B<XPA> distribution) must be running
prior to any attempts to access B<DS9>.  B<DS9> will automatically
start B<xpans> if it is in the user's path.

B<DS9> is available at C<http://hea-www.harvard.edu/RD/ds9/>.

B<XPA> is available at C<http://hea-www.harvard.edu/RD/xpa/>.

=head1 AUTHOR

Diab Jerius ( djerius@cfa.harvard.edu )

=head1 SEE ALSO

perl(1), IPC::XPA.

=cut
