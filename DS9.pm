package Image::DS9;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $use_PDL);


BEGIN {
  eval "use PDL::Types; use PDL::Core"; 
  $use_PDL = $@ ? 0 : 1;
  use vars qw( @ops );
  @ops = qw( @frame_ops @display_ops @tile_ops @extra_ops
	   @filetype_ops @scale_ops @mode_ops @orient_ops );
}


require Exporter;

@ISA = qw( Exporter );

@EXPORT = qw( );

use vars @ops, map { "${_}_dbg" } @ops;

@frame_ops = qw( 
		   FR_active
		   FR_all
		   FR_center
		   FR_clear
		   FR_delete
		   FR_first
		   FR_hide
		   FR_last
		   FR_new
		   FR_next
		   FR_prev
		   FR_refresh
		   FR_reset
		   FR_show
		  );

@display_ops = qw( D_blink D_tile D_single );

@tile_ops  = qw( T_Grid T_Column T_Row );

@extra_ops = qw( ON OFF YES NO );

@filetype_ops = qw( FT_MosaicImage FT_MosaicImages FT_Mosaic FT_Array );

@scale_ops = qw( S_linear S_log S_squared S_sqrt S_minmax S_zscale
		 S_user S_local S_global S_limits S_mode S_scope );

@mode_ops = qw( MB_pointer MB_crosshair MB_colorbar MB_pan
		MB_zoom MB_rotate MB_examine );

@orient_ops = qw( OR_X OR_Y OR_XY );

use vars qw( @all_ops );

eval "push \@all_ops, $_" foreach @ops;

for my $op ( @ops )
{
  eval "push ${op}_dbg, eval \$_ foreach ( ${op} )";
}


%EXPORT_TAGS = ( 
		frame => \@frame_ops,
		tile => \@tile_ops,
		filetype => \@filetype_ops,
		display => \@display_ops,
		scale => \@scale_ops,
		mode => \@mode_ops,
		orient => \@orient_ops,
		all => \@all_ops,
	       );

Exporter::export_ok_tags($_) foreach keys %EXPORT_TAGS;

$VERSION = '0.09';

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

  my %def_obj_attrs = ( Server => SERVER, 
			min_servers => 1,
			res_wanthash => 1,
			verbose => 0
		      );
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
  %{$_[0]->{res}};
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

  unless ( defined $state )
  {
    my %blink;
    my %single;
    my %tile;

    my $attrs = { chomp => 1, res_wanthash => 1 };

    # catch all of the exceptions and work around them
    # so as to get maximum data back to caller
    eval { %blink  = $self->Get( 'blink', $attrs )  };
    %blink = $self->res if $@;

    eval { %single = $self->Get( 'single', $attrs ) };
    %single = $self->res if $@;

    eval { %tile   = $self->Get( 'tile', $attrs )   };
    %tile = $self->res if $@;
    
    # create union of server list
    my %servers;
    $servers{$_}++ foreach ( keys(%blink), 
			     keys(%single), 
			     keys(%tile) );
    my @servers = keys %servers;

    my %results;

    foreach my $server ( @servers )
    {
      my @messages;

      unless ( exists $single{$server} &&
	       exists $tile{$server} &&
	       exists $blink{$server} ) 
      {
	$results{$server}= { 
			     name => $server,
			     message => 
			     "server did not exist during part of operation" };
	next;
      }
      
      for my $what ( \%blink, \%single, \%tile )
      {
	push @messages, $what->{$server}{message}
	  if exists $what->{$server}{message};
      }

      if ( @messages )
      {
	$results{$server} = {
			      name => $server,
			      message => join( '; ', @messages ) };
	next;
      }

      $results{$server} = { 
			   name => $server,
			   buf => 
			    $blink{$server}{buf}  eq 'yes' ? D_blink : 
			    $single{$server}{buf} eq 'yes' ? D_single :
			    $tile{$server}{buf}   eq 'yes' ? D_tile :
			      'unknown'
			    };
    }
    
    # handle errors now
    if ( grep { exists $_->{message} } values %results )
    {
      $self->{res} = \%results;
      croak( CLASS, '->display -- error obtaining status' );
    }

    unless ( wantarray() )
    {
      my ( $server ) = keys %results;
      return $results{$server}{buf};
    }
    
    else
    {
      return %results;
    }
  }

  else
  {
    
    croak( CLASS, '->display -- unknown display type' )
      if $state ne D_blink && $state ne D_tile && $state ne D_single;
    
    $self->Set( $state );
  }
}

use constant T_Grid	 => 'grid';
use constant T_Column	 => 'column';
use constant T_Row	 => 'row';

sub tile_mode
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return $self->Get( 'tile mode', 
		     { chomp => 1, res_wanthash => wantarray() } );
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
    return $self->Get( 'colormap', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  else
  {
    $self->Set( "colormap $colormap" );
  }
}

sub iconify
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return $self->Get( 'iconify', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  else
  {
    $self->Set( "iconify " . bool2str(str2bool($state)) );
  }
}

use constant FR_active	=> 'active';
use constant FR_all	=> 'all';
use constant FR_center  => 'center';
use constant FR_clear	=> 'clear';
use constant FR_delete  => 'delete';
use constant FR_first	=> 'first';
use constant FR_hide    => 'hide';
use constant FR_last	=> 'last';
use constant FR_new     => 'new';
use constant FR_next	=> 'next';
use constant FR_prev	=> 'prev';
use constant FR_refresh => 'refresh';
use constant FR_reset   => 'reset';
use constant FR_show	=> 'show';

sub frame
{
  my $self = shift;
  my $cmd = shift;

  unless( defined $cmd )
  {
    return $self->Get( 'frame', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'show' eq $cmd )
  {
    my $frame = shift;
    croak( CLASS, '->frame -- too few arguments' )
      unless defined $frame;
    $self->Set( "frame show $frame" );
  }

  elsif ( 'delete' eq $cmd )
  {
    my $frame = shift || '';
    $self->Set( "frame delete $frame" );
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
    return $self->Get( 'file',
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  else
  {
    $type ||= '';
    $self->Set( "file $type $file" );
  }


}

use constant MB_pointer		=> 'pointer';
use constant MB_crosshair	=> 'crosshair';
use constant MB_colorbar	=> 'colorbar';
use constant MB_pan		=> 'pan';
use constant MB_zoom		=> 'zoom';
use constant MB_rotate		=> 'rotate';
use constant MB_examine		=> 'examine';

sub mode
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return $self->Get( 'mode', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  else
  {
    $self->Set( "mode $state" );
  }
}


use constant OR_X	=> 'x';
use constant OR_Y	=> 'y';
use constant OR_XY	=> 'xy';

sub orient
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return $self->Get( 'orient', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  else
  {
    $self->Set( "orient $state" );
  }
}

sub rotate
{
  my $self = shift;
  my $what = shift;

  unless ( defined $what )
  {
    return $self->Get( 'rotate', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'abs' eq $what )
  {
    $what = shift;
    croak( CLASS, "->rotate: not enough arguments\n" )
      unless defined $what;
    $self->Set( "rotate to $what" );
  }

  elsif ( 'rel' eq $what )
  {
    $what = shift;
    croak( CLASS, "->rotate: not enough arguments\n" )
      unless defined $what;
    $self->Set( "rotate $what" );
  }

  else
  {
    croak( CLASS, "->rotate: too many arguments\n" )
      if @_;
    $self->Set( "rotate $what" );
  }
}

use constant S_linear	=> 'linear';
use constant S_log	=> 'log';
use constant S_squared	=> 'squared';
use constant S_sqrt	=> 'sqrt';
use constant S_minmax	=> 'minmax';
use constant S_zscale	=> 'zscale';
use constant S_user	=> 'user';
use constant S_local	=> 'local';
use constant S_global	=> 'global';
use constant S_limits	=> 'limits';
use constant S_mode	=> 'mode';
use constant S_scope	=> 'scope';

use vars qw( @scale_scopes @scale_modes @scale_algs );
@scale_scopes = ( S_local, S_global );
@scale_modes = ( S_minmax, S_zscale, S_user );
@scale_algs = ( S_linear, S_log, S_squared, S_sqrt );

sub scale
{
  my $self = shift;
  my $what = shift;

  unless ( defined $what )
  {
    return $self->Get( 'scale', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'scope' eq $what )
  {
    my $what = shift;

    unless ( defined $what )
    {
      return $self->Get( 'scale scope', 
		       { chomp => 1, res_wanthash => wantarray() } );
    }

    grep { $_ eq $what } @scale_scopes
      or croak( "unknown scale scope value: `$what'" );

    $self->Set( "scale scope $what" );
  }

  elsif ( 'limits' eq $what )
  {
    my $what = shift;

    unless ( defined $what )
    {
      return $self->Get( 'scale limits', 
		       { chomp => 1, res_wanthash => wantarray() } );
    }

    croak ( 'expected array ref for scale limit value' )
      unless 'ARRAY' eq ref($what);
    croak ( 'not enough values for scale limits' )
      unless $#{$what} >= 1;

    $self->Set( "scale limits $what->[0] $what->[1]" );
  }

  elsif( 'mode' eq $what )
  {
    my $what = shift;

    unless ( defined $what )
    {
      return $self->Get( 'scale mode', 
		       { chomp => 1, res_wanthash => wantarray() } );
    }

    grep { $_ eq $what } @scale_modes
      or croak( "unknown scale mode value: `$what'" );

    $self->Set( "scale mode $what" );
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

  unless ( defined $what )
  {
    return $self->Get( 'zoom', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'abs' eq $what )
  {
    $what = shift;
    croak( CLASS, "->zoom: not enough arguments\n" )
      unless defined $what;
    $self->Set( "zoom to $what" );
  }

  elsif ( 'rel' eq $what )
  {
    $what = shift;
    croak( CLASS, "->zoom: not enough arguments\n" )
      unless defined $what;
    $self->Set( "zoom $what" );
  }

  elsif ( 0 == $what )
  {
    $self->Set( "zoom to fit" );
  }

  else
  {
    croak( CLASS, "->zoom: too many arguments\n" )
      if @_;
    $self->Set( "zoom to $what" );
  }
}

sub Set
{
  my ( $self, $cmd, $buf ) = @_;

  print STDERR ( CLASS, "->Set: $cmd\n" )
    if $self->{verbose};

  my %res = $self->{xpa}->Set( $self->{Server}, $cmd, $buf, 
					    $self->{xpa_attrs} );

  # chomp messages
  foreach my $res ( values %res )
  {
    chomp $res->{message} if exists $res->{message};
  }

  if ( grep { defined $_->{message} } values %res )
  {
    $self->{res} = \%res;
    croak( CLASS, " -- error sending data to server" );
  }

  if ( keys %res < $self->{min_servers} )
  {
    $self->{res} = \%res;
    croak( CLASS, " -- fewer than ", $self->{min_servers}, 
	   " server(s) responded" )
  }
}

sub Get
{
  my ( $self, $cmd, $attr ) = @_;

  print STDERR ( CLASS, "->Get: $cmd\n" )
    if $self->{verbose};

  my %attr = ( $attr ? %$attr : () );

  $attr{res_wanthash} = $self->{res_wanthash} 
    unless defined $attr{res_wanthash};

  my %res = $self->{xpa}->Get( $self->{Server}, $cmd, 
			       $self->{xpa_attrs} );

  # chomp results
  foreach my $res ( values %res )
  {
    chomp $res->{message} if exists $res->{message};
    chomp $res->{buf} if exists $res->{buf} && exists $attr{chomp};
  }

  if ( grep { defined $_->{message} } values %res )
  {
    $self->{res} = \%res;
    croak( CLASS, " -- error sending data to server" );
  }
  
  if ( keys %res < $self->{min_servers} )
  {
    $self->{res} = \%res;
    croak( CLASS, " -- fewer than ", $self->{min_servers},
	   " servers(s) responded" )
  }

  unless ( $attr{res_wanthash} )
  {
    my ( $server ) = keys %res;
    return $res{$server}->{buf};
  }

  else
  {
    return %res;
  }
}


sub str2bool
{
  my $string = lc shift;

  $string eq 'yes' or $string eq 'on' or $string eq '1';
}

sub bool2str
{
  my $bool = shift;
  $bool ? 'yes' : 'no';
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=pod

=head1 NAME

Image::DS9 - interface to the DS9 image display and analysis program

=head1 SYNOPSIS

  use Image::DS9;
  use Image::DS9 qw( :<group> );  # import constants from group <group>
  use Image::DS9 qw( :all );	  # import all constants

  $dsp = new Image::DS9;
  $dsp = new Image::DS9( \%attrs );

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

Commands sent to DS9 are sent as strings.  To prevent typos (and other
unwanted sideeffects) B<Image::DS9> makes many of the commands and
subcommands available as Perl constants -- mistype these and the
compiler will complain, not B<DS9>.

Predefined constants may be imported when the B<Image::DS9> package
is loaded, by specifying one or more of the following tags:
C<frame>,
C<tile>,
C<filetype>,
C<display>,
C<scale>,
C<mode_ops>,
C<orient_ops>,
or C<all>.

For example:

	use Image::DS9 qw( :frame :tile :filetype :display );

The C<frame> group imports
C<FR_active>,
C<FR_all>,
C<FR_center>,
C<FR_clear>,
C<FR_delete>,
C<FR_first>,
C<FR_hide>,
C<FR_last>,
C<FR_new>,
C<FR_next>,
C<FR_prev>,
C<FR_refresh>,
C<FR_reset>,
C<FR_show>.

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
C<S_log>,
C<S_squared>,
C<S_sqrt>,
C<S_minmax>,
C<S_zscale>,
C<S_user>,
C<S_local>,
C<S_global>,
C<S_limits>,
C<S_mode>,
C<S_scope>.

The C<mode_ops> group imports
C<MB_pointer>,
C<MB_crosshair>,
C<MB_colorbar>,
C<MB_pan>,
C<MB_zoom>,
C<MB_rotate>,
C<MB_examine>.

The C<orient-ops> group imports
C<OR_X>,
C<OR_Y>,
C<OR_XY>.

The C<all> group imports all of the above groups, as well as
C<ON>,
C<OFF>,
C<YES>
C<NO>.

=head2 Boolean values

Some methods take boolean values; these may be the strings C<on>, C<off>,
C<yes>, C<no>, or the integers C<1> or C<0>.


=head2 Return values

Because a single B<Image::DS9> object may communicate with multiple
instances of B<DS9>, most return values are hashes, rather
than scalars.  The hash has as keys the names of the servers, with the
values being references to hashes with the keys C<name>, C<buf> and C<message>.
The C<buf> key will be present if there are no errors for that server,
the C<message> if there were. 

For example,

	use Data::Dumper;
	%colormaps = $dsp->colormap;
	print Dumper \@colormaps;

yields

	$VAR1 = {
	         'DS9:ds9 838e2ab4:32832' =>
	          {
	            'name' => 'DS9:ds9 838e2ab4:32832',
	            'buf' => 'Grey'
	          }
	        };

If you know that there is only one server out there  (for example,
if the object was created with B<max_servers> set to 1), you can
call a method in a scalar environment, and it will directly return
the value:

	$colormap = $dsp->colormap;

If there is more than one server, you'll get the results for a randomly
chosen server.

Sending data usually doesn't result in a return:

	$dsp->colormap( 'Grey' );


=head2 Error Returns

In case of error, an exception is thrown via B<croak()>.  
The B<res()> method will return a hash, keyed off of the servers name.
For each server which had an error, the hash value will be a reference
to a hash containing the keys C<name> and C<message>; the latter
will contain error information.  For those commands which return
data, and for those servers which did not have an error, the
C<buf> key will be available.

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

=item colormap

  $dsp->colormap( $colormap );
  @colormaps = $dsp->colormap;

If an argument is specified, it should be the name of a colormap (case
is not important).  If no argument is specified, the current colormaps
for all of the B<DS9> instances is returned, as a list containing
references to hashes with the keys C<name> and C<buf>.  The latter
will contain the colormap name.


=item display

  $dsp->display( $state );
  %displays = $dsp->display;

If an argument is specified, this call will change how the data are
displayed. C<$state> may be one of the constants C<D_blink>,
C<D_tile>, or C<D_single> (or, equivalently, 'blink', 'tile', 'single'
).  The constants are available by importing the C<display> tag.

If no argument is specified, the current display states of the B<DS9> servers 
are returned (see L</Return values> for the format).  The state is
will be returned as a string equivalent to the constants C<D_blink>,
C<D_tile> or C<D_single>.  For instance:

  my $ds9 = new DS9( { max_servers => 1 } );

  print "We're blinking!\n" if D_blink eq $ds9->display;


=item file

  $dsp->file( $file );
  $dsp->file( $file, $type );
  %files = $dsp->file;

Display the specified C<$file>.  The file type is optional, and may be
one of the following constants: C<FT_MosaicImage>, C<FT_MosaicImages>,
C<FT_Mosaic>, C<FT_Array> (or one of the strings C<'mosaicimage'>,
C<'mosaicimages'>, C<'mosaic'>, or C<'array'> ). (Import the C<filetype>
tag to get the constants).

If called without a value, it will return the current file name loaded
for the current frame.


=item frame

  @frames = $dsp->frame;

  # perform a frame operation with no arguments
  $dsp->frame( $frame_op );

  # show the specified frame
  $dsp->frame( show => $frame );

  # delete the current frame
  $dsp->frame( FR_delete );
    
  # delete the specified frame
  $dsp->frame( delete => $frame );

  # delete all of the frames
  $dsp->frame( delete => FR_all );

Command B<DS9> to do frame operations.  Frame operations are nominally
strings.  As B<DS9> will interpret any string which isn't a frame operation
as the name of frame to switch to (or create, if necessary), B<Image::DS9>
provides constants for the standard operations to prevent typos.  See
L</Constants>.
Otherwise, use the strings 
C<active>,
C<all>,
C<center>,
C<clear>,
C<delete>,
C<hide>,
C<new>,
C<refresh>,
C<reset>,
C<show>,
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

=item iconify

  $iconify_state = $dsp->iconify;
  %iconify_state = $dsp->iconify;
  $dsp->iconify($bool);

With a boolean argument, specify the iconification state, else
return it.

=item mode

  $mode = $dsp->mode;
  $dsp->mode( $state );

Change (or query) the first mouse button mode state.  Predefined
states are available via the C<mode_ops> group; see L</Constants>.

=item orient

  $state = $dsp->orient;
  $dsp->orient( $state );

Change (or query) the orientation of the current frame. Predefined
states are available via the C<orient_ops> group; see L</Constants>.

=item rotate

  $rotate = $dsp->rotate;
  $dsp->rotate( abs => $rotate );
  $dsp->rotate( rel => $rotate );
  $dsp->rotate( $rotate );

Change or query the rotation angle (in degrees) for the current frame.
A rotatation may be absolute or relative; this is explicitly specified
in the second and third forms of the method invocation.  If not
specified (as in the last form) it is relative.

If no argument is specified, it returns the rotatation angle for the current
frame.

=item res

  $res = $dsp->res;

In case of error, the returned results from the failing B<XPA> call
are available via this method.  It returns a reference to an
array of hashes, one per instance of B<DS9> addressed by the object.
See the B<IPC::XPA> documentation for more information on what
the hashes contain.


=item scale

  $dsp->scale( $algorithm );
  $dsp->scale( S_limits => [ $min, $max ] );
  $dsp->scale( S_mode => $mode );
  $dsp->scale( S_scope => $scope );

  %scale = $dsp->scale;
  %limits = $dsp->scale( S_limits );
  %mode = $dsp->scale( S_mode );
  %scope = $dsp->scale( S_scope );

This specifies how the data will be scaled.  C<$algorithm> may
be one of the constants 
C<S_linear>,
C<S_log>,
C<S_squared>,
C<S_sqrt>
(or, equivalently, 
C<'linear'>,
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

The constants are available if the C<scale> tag is imported (see
L</Constants>).  The second set of invocations shown above illustrates
how to determine the current values of the scale parameters.

=item tile_mode

  $dsp->tile_mode( $mode );

The tiling mode may be specified by setting C<$mode> to C<T_Grid>,
C<T_Column>, or C<T_Row>.  These constants are available if the
C<tile_op> tags are imported.  Otherwise, use C<'grid'>, c<'column'>,
or C<'row'>.  If called without a value, it will return the
current tiling mode.

=item zoom

  $zoom = $dsp->zoom;
  $dsp->zoom( abs => $zoom );
  $dsp->zoom( rel => $zoom );
  $dsp->zoom( $zoom );

This changes the zoom value for the current frame.  C<$zoom> is a
positive numerical value.  A zoom value may be absolute or relative.
This is explicitly specified in the second and third forms of the
method invocation.  If not specified (as in the last form)
it is absolute.  To zoom such that the image fits with in the frame,
specify a zoom value of C<0>.

If no argument is specified, it returns the zoom value for the current
frame.

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
