package Image::DS9;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $use_PDL);

BEGIN {
  eval "use PDL::Types; use PDL::Core"; 
  $use_PDL = $@ ? 0 : 1;
}

require Exporter;

@ISA = qw( Exporter );

# export nothing by default
@EXPORT = qw( );

# each method which defines tags has a BEGIN
# block which preloads EXPORT_TAGS.  what's left is just
# the non-method specific stuff, i.e. the extras...
use constant ON		=> 'on';
use constant OFF	=> 'off';
use constant YES	=> 'yes';
use constant NO		=> 'no';

our @extra_tags = qw( ON OFF YES NO );

our %bool = ( 0    , 0,
	      1    , 1,
	      YES  , 1,
	      NO   , 0,
	      ON   , 1,
	      OFF  , 0 );


$EXPORT_TAGS{extra} = \@extra_tags;

# Coordinate systems
use constant Coord_fk4      => 'fk4';
use constant Coord_fk5      => 'fk5';
use constant Coord_icrs     => 'icrs';
use constant Coord_galactic => 'galactic';
use constant Coord_ecliptic => 'ecliptic';
use constant Coord_linear   => 'linear';
use constant Coord_image    => 'image';
use constant Coord_physical => 'physical';
our @coords = qw( Coord_fk4 Coord_fk5 Coord_icrs Coord_galactic 
		  Coord_ecliptic Coord_linear Coord_image
		  Coord_physical );
$EXPORT_TAGS{coords} = \@coords;
our %Coords = 
  map { $_, 1 } ( Coord_fk4, Coord_fk5, Coord_icrs, Coord_galactic, 
		  Coord_ecliptic, Coord_linear, Coord_image,
		  Coord_physical );

our %WCSCoords =
  map { $_, 1 } ( Coord_fk4, Coord_fk5, Coord_icrs, Coord_galactic, 
		    Coord_ecliptic, Coord_linear );

# Coordinate formats
use constant CoordFmt_degrees     => 'degrees';
use constant CoordFmt_sexagesimal => 'sexagesimal';
our @coord_fmts = qw( CoordFmt_degrees CoordFmt_sexagesimal );
our %CoordFmts = map { $_, 1 } ( CoordFmt_degrees, CoordFmt_sexagesimal );
$EXPORT_TAGS{coord_fmts} = \@coord_fmts;

# load EXPORT_OK with all of the symbols
Exporter::export_ok_tags($_) foreach keys %EXPORT_TAGS;

# now, create a tag which will import all of the symbols
$EXPORT_TAGS{all} = \@EXPORT_OK;

$VERSION = '0.13';

use Carp;
use Data::Dumper;
use IPC::XPA;
use constant SERVER => 'ds9';


#####################################################################

# Preloaded methods go here.

sub _flatten_hash
{
  my ( $hash ) = @_;

  return '' unless keys %$hash;

  join( ',', map { "$_=" . $hash->{$_} } keys %$hash );
}

#####################################################################

# create new XPA object
{

  my %def_obj_attrs = ( Server => SERVER,
			WaitTimeOut => 30,
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
    
    croak( __PACKAGE__, "->new -- error creating XPA object" )
      unless defined $self->{xpa};
    
    $self->{xpa_attrs}{max_servers} = $self->nservers || 1;

    $self->set_attrs($u_attrs);

    $self->wait( )
      if defined $self->{Wait};

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

#####################################################################

sub nservers
{
  my $self = shift;

  $self->{xpa}->Access( $self->{Server}, 'gs' );
}

#####################################################################

sub res
{
  %{$_[0]->{res}};
}

#####################################################################

sub wait
{
  my $self = shift;
  my $timeout = shift || $self->{WaitTimeOut};

  unless( $self->nservers )
  {
    my $cnt = 0;
    sleep(1)
      until $self->nservers >= $self->{min_servers}
            || $cnt++ > $timeout;
  }

  return $self->nservers >= $self->{min_servers};
}


#####################################################################

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
    
    if ( $use_PDL && ref( $image ) && UNIVERSAL::isa( $image, 'PDL' ))
    {
      $attrs{bitpix} = $map{$image->get_datatype};
      ($attrs{xdim}, $attrs{ydim}) = $image->dims;
      $data = ${$image->get_dataref};
      $attrs{ydim} = 1 unless defined $attrs{ydim};
    }
    
    if ( exists $attrs{dim} )
    {
      delete $attrs{xdim};
      delete $attrs{ydim};
    }

    my @notset = grep { ! defined $attrs{$_} } keys %attrs;
    croak( __PACKAGE__, 
	   '->array -- the following attributes were not defined: ',
	   join( ',', map { "'$_'" } @notset) )
      if @notset;

    $self->Set( 'array ['._flatten_hash(\%attrs).']', $data );
  }
}

#####################################################################

use constant B_about => 'about';
use constant B_buffersize => 'buffersize';
use constant B_cols => 'cols';
use constant B_factor => 'factor';
use constant B_filter => 'filter';
use constant B_function => 'function';
use constant B_average => 'average';
use constant B_sum => 'sum';
use constant B_to_fit => 'to fit';

BEGIN
{
  my @symbols = qw( B_about B_buffersize B_cols B_factor B_filter
		 B_function B_average B_sum B_fit);
  $EXPORT_TAGS{bin} = \@symbols;

  my %funcs = map { $_, 1 } ( B_sum, B_average );

  # the number of arguments for the various modes
  my %Mode = (
	       B_about, 2,
	       B_buffersize, 1,
	       B_cols, 2,
	       B_factor, 1,
	       B_filter, 1,
	       B_function, 1,
	       B_to_fit, 0
	       );

  sub bin
  {
    my $self = shift;
    my $mode = shift;

    croak( __PACKAGE__, "->bin: must specify mode\n" )
      unless defined $mode;

    croak( __PACKAGE__, "->bin: unknown mode: `$mode'\n" )
      unless defined $Mode{$mode};

    # bin to fit is the odd one, it takes no arguments, and
    # isn't a query
    if( B_to_fit eq $mode )
    {
      croak( __PACKAGE__, "->bin: $mode takes no arguments\n" )
	if @_;

      $self->Set( "bin $mode" );
    }

    # no arguments, must want to query info
    elsif ( ! @_ )
    {
      # accept query unless there are no arguments (as in bin to fit)
      croak( __PACKAGE__, "->bin: not a proper mode for queries: $mode\n" )
	unless $Mode{$mode};
      
      my %results = $self->_Get( "bin $mode", 
			      { chomp => 1, res_wanthash => 1 } );

      for my $res ( values %results )
      {
	$res->{buf} = _splitbuf( $res->{buf} )
	  if $Mode{$mode} > 1;
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
      croak( __PACKAGE__, "->bin: $mode requires $Mode{$mode} arguments\n" )
	unless $Mode{$mode} == @_;
      
      local $" = ' ';
      $self->Set( "bin $mode @_" );
    }
  }
}


#####################################################################

use constant CM_invert => 'invert';

BEGIN
{
  my @symbols = qw( CM_invert );
  $EXPORT_TAGS{colormap} = \@symbols;
}

sub colormap
{
  my ( $self, $colormap, $state ) = @_;
  
  unless ( defined $colormap )
  {
    return $self->_Get( 'cmap', 
		      { chomp => 1, res_wanthash => wantarray() } );
  }
  
  elsif ( CM_invert eq $colormap )
  {
    if ( defined $state )
    {
      $state = str2bool(bool2str($state));
      $self->Set( "cmap invert $state" );
    }
    else
    {
      return 
	str2bool($self->_Get( 'cmap invert',
			    { chomp => 1, res_wanthash => wantarray() } ));
    }
  }
  
  else
  {
    $self->Set( "cmap $colormap" );
  }
}

#####################################################################


sub crosshair
{
  my $self = shift;
  
  # query
  if ( @_ <= 1 )
  {
    my $coords = shift;
    croak( __PACKAGE__, 
	   "->crosshair: unknown coordinate system `$coords'\n" )
      if defined $coords && !$Coords{$coords};
    
    $coords ||= '';
    my %results = $self->_Get( "crosshair $coords", 
			     { chomp => 1, res_wanthash => 1 } );
    
    for my $res ( values %results )
    {
      $res->{buf} = _splitbuf( $res->{buf} );
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
  
  # set 
  else
  {
    my ( $x, $y, $coords ) = @_;
    croak( __PACKAGE__, 
	   "->crosshair: unknown coordinate system `$coords'\n" )
      if defined $coords && !$Coords{$coords};
    $coords ||= '';
    
    $self->Set( "crosshair $x $y $coords" );
  }
}

#####################################################################


sub cursor
{
  my $self = shift;

  croak( __PACKAGE__, "->cursor: two arguments required!\n" )
    unless 2 == @_;

  local $" = ' ';
  $self->Set( "cursor @_" );
}


#####################################################################

use constant D_tile   => 'tile';
use constant D_single => 'single';
use constant D_blink  => 'blink';

BEGIN 
{ 
  my @symbols = qw( D_blink D_tile D_single );
  $EXPORT_TAGS{ display } = \@symbols;

  my %State = map { $_,1 } ( D_tile, D_single, D_blink );
  
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
      eval { %blink  = $self->_Get( D_blink, $attrs )  };
      %blink = $self->res if $@;
      
      eval { %single = $self->_Get( D_single, $attrs ) };
      %single = $self->res if $@;
      
      eval { %tile   = $self->_Get( D_tile, $attrs )   };
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
	croak( __PACKAGE__, '->display -- error obtaining status' );
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
      
      croak( __PACKAGE__, "->display: unknown state `$state'\n" )
	unless exists $State{$state};
      
      $self->Set( $state );
    }
  }
}

#####################################################################

use constant FT_MosaicImage	=> 'mosaicimage';
use constant FT_MosaicImages	=> 'mosaicimages';
use constant FT_Mosaic		=> 'mosaic';
use constant FT_Array		=> 'array';
use constant FT_Save		=> 'save';

BEGIN 
{
  my @symbols = qw( FT_MosaicImage FT_MosaicImages FT_Mosaic FT_Array FT_Save);
  $EXPORT_TAGS{filetype} = \@symbols;
  my %Type = map { $_,1 }
             ( FT_MosaicImage, FT_MosaicImages, FT_Mosaic, FT_Array, FT_Save, 
	       '' );

  sub file
  {
    my ( $self, $file, $type ) = @_;
    
    unless ( defined $file )
    {
      return $self->_Get( 'file',
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    else
    {
      $type ||= '';

      croak( __PACKAGE__, "->file: unknown type `$type'\n" )
	unless exists $Type{$type};

      $self->Set( "file $type $file" );
    }
  }
  
}

#####################################################################

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

BEGIN { 
  my @symbols = qw( FR_active FR_all FR_center FR_clear FR_delete
		       FR_first FR_hide FR_last FR_new FR_next FR_prev 
		       FR_refresh FR_reset FR_show );
  $EXPORT_TAGS{frame} = \@symbols;

}


sub frame
{
  my $self = shift;
  my $cmd = shift;

  unless( defined $cmd )
  {
    return $self->_Get( 'frame', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( FR_all eq $cmd )
  {
      my %results = $self->_Get( "frame all", 
			      { chomp => 1, res_wanthash => 1 } );

      for my $res ( values %results )
      {
	$res->{buf} = _splitbuf( $res->{buf} );
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

  elsif ( FR_show eq $cmd )
  {
    my $frame = shift;
    croak( __PACKAGE__, '->frame: too few arguments' )
      unless defined $frame;
    $self->Set( "frame show $frame" );
  }

  elsif ( FR_hide eq $cmd )
  {
    my $frame = shift || '';

    croak( __PACKAGE__, '->frame: too many arguments' )
      if @_;

    $self->Set( "frame hide $frame" );
  }

  elsif ( FR_delete eq $cmd )
  {
    my $frame = shift || '';

    croak( __PACKAGE__, '->frame: too many arguments' )
      if @_;

    $self->Set( "frame delete $frame" );
  }

  else
  {
    croak( __PACKAGE__, '->frame: too many arguments' )
      if @_;
    $self->Set( "frame $cmd" );
  }


}

#####################################################################

sub iconify
{
  my ( $self, $state ) = @_;

  unless ( defined $state )
  {
    return str2bool($self->_Get( 'iconify', 
		     { chomp => 1, res_wanthash => wantarray() } ));
  }

  else
  {
    $self->Set( "iconify " . bool2str(str2bool($state)) );
  }
}

#####################################################################

sub lower
{
  my $self = shift;
  $self->Set( 'lower' );
}

#####################################################################

use constant MB_pointer		=> 'pointer';
use constant MB_crosshair	=> 'crosshair';
use constant MB_colorbar	=> 'colorbar';
use constant MB_pan		=> 'pan';
use constant MB_zoom		=> 'zoom';
use constant MB_rotate		=> 'rotate';
use constant MB_examine		=> 'examine';

BEGIN
{
  my @symbols = qw( MB_pointer MB_crosshair MB_colorbar MB_pan
		      MB_zoom MB_rotate MB_examine );

  $EXPORT_TAGS{mode} = \@symbols;

  my %State = map {$_, 1 }( MB_pointer, MB_crosshair, MB_colorbar, MB_pan,
			    MB_zoom, MB_rotate, MB_examine );
  
  sub mode
  {
    my ( $self, $state ) = @_;
    
    unless ( defined $state )
    {
      return $self->_Get( 'mode', 
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    else
    {
      croak( __PACKAGE__, "->mode: unknown mode `$state'\n" )
	unless exists $State{$state};

      $self->Set( "mode $state" );
    }
  }
}
#####################################################################


use constant OR_X	=> 'x';
use constant OR_Y	=> 'y';
use constant OR_XY	=> 'xy';

BEGIN
{
  my @symbols = qw( OR_X OR_Y OR_XY );
  $EXPORT_TAGS{orient} = \@symbols;

  my %State = map {$_,1} ( OR_X, OR_Y, OR_XY );
  
  sub orient
  {
    my ( $self, $state ) = @_;
    
    unless ( defined $state )
    {
      return $self->_Get( 'orient', 
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    else
    {
      croak( __PACKAGE__, "->orient: unknown orientation `$state'\n" )
	unless exists $State{$state};

      $self->Set( "orient $state" );
    }
  }
  
}

#####################################################################

sub raise
{
  my $self = shift;
  $self->Set( 'raise' );
}

#####################################################################

use constant Rg_coord       => 'coord';
use constant Rg_coordformat => 'coordformat';
use constant Rg_deleteall   => 'deleteall';
use constant Rg_delim       => 'delim';
use constant Rg_ds9         => 'ds9';
use constant Rg_file        => 'file';
use constant Rg_load        => 'load';
use constant Rg_format      => 'format';
use constant Rg_moveback    => 'moveback';
use constant Rg_movefront   => 'movefront';
use constant Rg_nl          => 'nl';
use constant Rg_pros        => 'pros';
use constant Rg_save        => 'save';
use constant Rg_saoimage    => 'saoimage';
use constant Rg_saotng      => 'saotng';
use constant Rg_selectall   => 'selectall';
use constant Rg_selectnone  => 'selectnone';
use constant Rg_semicolon   => 'semicolon';

use constant Rg_return_fmt   => 'return_fmt';
use constant Rg_raw         => 'raw';

BEGIN
{
  my @symbols = qw(
		   Rg_coord
		   Rg_coordformat
		   Rg_deleteall
		   Rg_delim
		   Rg_ds9
		   Rg_file
		   Rg_format
		   Rg_load
		   Rg_moveback
		   Rg_movefront
		   Rg_nl
		   Rg_pros
		   Rg_saoimage
		   Rg_saotng
		   Rg_save
		   Rg_selectall
		   Rg_selectnone
		   Rg_semicolon

		   Rg_return_fmt
		   Rg_raw
		  );


  $EXPORT_TAGS{regions} = \@symbols;
  
  my %reg_fmts = map { $_, 1 } ( Rg_ds9, Rg_saotng, Rg_saoimage, Rg_pros );
  
  my @Attr =  ( Rg_format, Rg_coord, Rg_coordformat, Rg_delim );
  my %Attr = map { $_, 1 } @Attr;
  
  my %delim = map { $_, 1 } ( Rg_semicolon, Rg_nl );
  
  sub regions
  {
    my $self = shift;
    my $what = shift;
    
    # unadulterated query
    if ( ! defined $what )
    {
      return $self->_Get( 'regions', 
			{ chomp => 0, res_wanthash => wantarray() } );
    }
    
    # complications hidden in references...
    elsif ( ref $what )
    {
      # query with attributes
      if ( 'HASH' eq ref $what )
      {
	my $cmd = '';
	
	# filter out our own attributes. currently this
	# is very primitive and is just a place holder
	my %attr = %$what;
	if ( exists $attr{Rg_return_fmt} )
	{
	  croak( __PACKAGE__, 
		 "->regions: unknown parse format $attr{Rg_return_fmt}\n" )
	    unless $attr{Rg_return_fmt} eq Rg_raw;
	  delete $attr{Rg_return_fmt};
	}

	# check attributes
	while( my ( $key, $value ) = each %attr )
	{
	  croak( __PACKAGE__, "->regions: unknown attribute `$key'\n" )
	    unless exists $Attr{$key};
	  
	  $cmd .= "-$key $value";
	}
	
	return $self->_Get( "regions $cmd",
			  { chomp => 0, res_wanthash => wantarray() } );
      }
      
      # buffer to send
      elsif ( 'SCALAR' eq ref $what )
      {
	$self->Set( "regions", "$$what\n" );
      }
      
      else
      {
	croak( __PACKAGE__, 
	       "->regions: can't deal with passed reference type: `", 
	       ref($what), "'\n" );
      }
    }
    
    # specific query
    elsif ( exists $Attr{$what} )
    {
      return $self->_Get( "regions $what", 
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    # 
    elsif ( Rg_selectall  eq $what ||
	    Rg_selectnone eq $what )
    {
      croak( __PACKAGE__, "->regions: too many arguments\n" )
	if @_;
      
      $self->Set( "regions $what" );
    }
    
    elsif ( Rg_file eq $what || 
	    Rg_load eq $what ||
	    Rg_save eq $what
	  )
    {
      croak( __PACKAGE__, "->regions($what) requires one argument\n" )
	unless  1 == @_;
      
      $self->Set( "regions $what $_[0]" );
    }
    
    elsif ( Rg_format eq $what )
    {
      croak( __PACKAGE__, "->regions($what) requires one argument\n" )
	unless  1 == @_;
      
      croak( __PACKAGE__, "->regions($what): unknown format `$_[0]'\n" )
	unless  exists $reg_fmts{$_[0]};
      
      $self->Set( "regions $what $_[0]" );
    }
    
    elsif ( Rg_coord eq $what )
    {
      croak( __PACKAGE__, "->regions($what) requires one argument\n" )
	unless  1 == @_;
      
      croak( __PACKAGE__, 
	     "->regions($what): unknown coordinate system `$_[0]'\n" )
	unless  exists $Coords{$_[0]};
      
      $self->Set( "regions $what $_[0]" );
    }
    
    elsif ( Rg_coordformat eq $what )
    {
      croak( __PACKAGE__, "->regions($what) requires one argument\n" )
	unless  1 == @_;
      
      croak( __PACKAGE__, 
	     "->regions($what): unknown coordinate system format `$_[0]'\n" )
	unless  exists $CoordFmts{$_[0]};
      
      $self->Set( "regions $what $_[0]" );
    }
    
    elsif ( Rg_delim eq $what )
    {
      croak( __PACKAGE__, "->regions($what) requires one argument\n" )
	unless  1 == @_;
      
      croak( __PACKAGE__, 
	     "->regions($what): unknown delimiter `$_[0]'\n" )
	unless  exists $delim{$_[0]};
      
      $self->Set( "regions $what $_[0]" );
    }
  }
}

#####################################################################

sub rotate
{
  my $self = shift;
  my $what = shift;

  unless ( defined $what )
  {
    return $self->_Get( 'rotate', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'abs' eq $what )
  {
    $what = shift;
    croak( __PACKAGE__, "->rotate: not enough arguments\n" )
      unless defined $what;
    $self->Set( "rotate to $what" );
  }

  elsif ( 'rel' eq $what )
  {
    $what = shift;
    croak( __PACKAGE__, "->rotate: not enough arguments\n" )
      unless defined $what;
    $self->Set( "rotate $what" );
  }

  else
  {
    croak( __PACKAGE__, "->rotate: too many arguments\n" )
      if @_;
    $self->Set( "rotate $what" );
  }
}

#####################################################################

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
use constant S_datasec  => 'datasec';


BEGIN 
{ 
  my @symbols = qw( S_linear S_log S_squared S_sqrt S_minmax S_zscale
		    S_user S_local S_global S_limits S_mode S_scope 
		    S_datasec
		  );

  $EXPORT_TAGS{scale} = \@symbols;
  
  my %scopes = map { $_, 1 } ( S_local, S_global );
  my %modes  = map { $_, 1 } ( S_minmax, S_zscale, S_user );
  my %algs   = map { $_, 1 } ( S_linear, S_log, S_squared, S_sqrt );
  
  sub scale
  {
    my $self = shift;
    my $what = shift;
    
    unless ( defined $what )
    {
      return $self->_Get( 'scale', 
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    elsif ( S_scope eq $what )
    {
      my $what = shift;
      
      unless ( defined $what )
      {
	return $self->_Get( 'scale scope', 
			  { chomp => 1, res_wanthash => wantarray() } );
      }
      
      croak( __PACKAGE__, "->scale: unknown scale scope value: `$what'\n" )
	unless exists $scopes{$what};
      
      $self->Set( "scale scope $what" );
    }
    
    elsif ( S_datasec eq $what )
    {
      my $arg = shift;
      
      unless ( defined $arg )
      {
	return $self->_Get( "scale $what",
			  { chomp => 1, res_wanthash => wantarray() } );
      }
      
      croak( __PACKAGE__, "->scale: illegal boolean value: `$arg'\n" )
	unless exists $bool{lc $arg};
      
      $self->Set( "scale $what $arg" );
    }
    

    elsif ( S_limits eq $what )
    {
      my $what = shift;
      
      unless ( defined $what )
      {
	my %results = $self->_Get( 'scale limits', 
				 { chomp => 1, res_wanthash => 1 } );
	
	for my $res ( values %results )
	{
	  $res->{buf} = _splitbuf( $res->{buf} );
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
      
      croak ( __PACKAGE__, 
	      '->scale: expected array ref for scale limit value' )
	unless 'ARRAY' eq ref($what);

      croak ( __PACKAGE__, '->scale: not enough values for scale limits' )
	unless $#{$what} >= 1;
      
      $self->Set( "scale limits $what->[0] $what->[1]" );
    }
    
    elsif( S_mode eq $what )
    {
      my $what = shift;
      
      unless ( defined $what )
      {
	return $self->_Get( 'scale mode', 
			  { chomp => 1, res_wanthash => wantarray() } );
      }
      
      croak( __PACKAGE__, "->scale: unknown scale mode value: `$what'\n" )
	unless exists $modes{$what};

      $self->Set( "scale mode $what" );
    }

    else
    {
      croak( __PACKAGE__, "->scale: unknown scale algorithm `$what'\n" )
	unless exists $algs{$what};

      $self->Set( "scale $what" );
    }
  }
}

#####################################################################

use constant T_grid	 => 'grid';
use constant T_column	 => 'column';
use constant T_row	 => 'row';
use constant T_gap	 => 'gap';
use constant T_layout	 => 'layout';
use constant T_mode	 => 'mode';
use constant T_auto	 => 'automatic';
use constant T_manual	 => 'manual';


BEGIN 
{ 
  my @symbols  = qw(
		    T_grid T_column T_row T_gap T_layout T_mode T_auto T_manual
		   );
  $EXPORT_TAGS{tile} = \@symbols;

  # the number of arguments for grid parameters
  my %Mode = (
	      T_mode,   1,
	      T_layout, 2,
	      T_gap,    1
	     );
  
  sub tile_mode
  {
    my $self  = shift;
    my $state = shift;
    
    unless ( defined $state )
    {
      return $self->_Get( 'tile mode', 
			{ chomp => 1, res_wanthash => wantarray() } );
    }
    
    elsif ( T_column eq $state || T_row eq $state )
    {
      $self->Set( "tile mode $state" );
    }
    
    elsif ( T_grid eq $state )
    {
      my $what = shift;
      
      unless ( defined $what )
      {
	$self->Set( "tile mode $state" );
	return;
      }

      croak( __PACKAGE__,
	     "->tile_mode: unknown $state modifier `$what'\n" )
	unless defined $Mode{$what};

      # want current state for $state $what
      if ( 0 == @_ )
      {
	my %results = $self->_Get( "tile $state $what",
				 { chomp => 1, res_wanthash => 1 } );
	
	for my $res ( values %results )
	{
	  $res->{buf} = _splitbuf( $res->{buf} )
	    if $Mode{$what} > 1;
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

      # else, want to set it

      croak( __PACKAGE__, 
	     "->tile_mode: `$state $what' requires $Mode{$what} arguments\n" )
	unless 0 == @_ || $Mode{$what} == @_;

      if ( T_mode eq $what )
      {
	croak( __PACKAGE__,
	       "->tile_mode: unknown $state $what: $_[0]\n" )
	  unless T_auto eq $_[0] || T_manual eq $_[0];

	$self->Set( "tile $state $what $_[0]" );
      }

      else
      {
	$self->Set( "tile $state $what ". join( ' ', @_ ) );
      }
      
    }

    else
    {
      croak( __PACKAGE__, "->tile_mode: unknown mode `$state'\n" );
    }

  }
  
}

#####################################################################

use constant WCS_align   => 'align';
use constant WCS_format  => 'format';
use constant WCS_reset   => 'reset';
use constant WCS_replace => 'replace';
use constant WCS_append  => 'append';

BEGIN
{
  my @symbols = qw( WCS_align WCS_format WCS_reset WCS_replace WCS_append );
  $EXPORT_TAGS{wcs} = \@symbols;
}


sub wcs
{
  my $self = shift;
  my $what = shift;

  # query?
  if ( ! defined $what ||
       ( WCS_align eq $what || WCS_format eq $what ) && 0 == @_ )
  {
    $what ||= '';
    return $self->_Get( "wcs $what", { chomp => 1, res_wanthash => wantarray() } );
  }
       
  # set the coordinate system
  elsif ( exists $WCSCoords{$what} )
  {
    croak ( __PACKAGE__, "->wcs($what) takes no additional arguments\n" )
      if @_ > 0;
    $self->Set( "wcs $what" );
  }

  elsif( WCS_align eq $what )
  {
    my $state = shift;
    croak( __PACKAGE__, "->wcs($what): too many arguments\n" )
      if @_;

    $self->Set( "wcs $what " . bool2str(str2bool($state)) );
  }

  elsif( WCS_format eq $what )
  {
    my $format = shift;

    croak( __PACKAGE__, "->wcs($what): unknown coord format `$format'\n" )
      unless exists $CoordFmts{$format};

    croak( __PACKAGE__, "->wcs($what): too many arguments\n" )
      if @_;

    $self->Set( "wcs $what $format" );
  }

  elsif( WCS_reset eq $what )
  {
    $self->Set( "wcs $what" );
  }

  elsif( WCS_replace eq $what ||
	 WCS_append  eq $what )
  {

    croak( __PACKAGE__, "->wcs($what): incorrect number of arguments\n" )
      unless 1 == @_;

    my $buf = shift;

    if ( ref $buf )
    {
      # if a reference to a scalar, shove it along directly
      if ( 'SCALAR' eq ref $buf )
      {
	$self->Set( "wcs $what", $$buf );
      }
      
      # turn hash into appropriate string
      elsif ( 'HASH' eq ref $buf )
      {
	my $wcs;

	while( my ($key, $val ) = each %$buf )
	{
	  # aggressively remove surrounding apostrophes
	  $val =~ s/^'+//;
	  $val =~ s/'+$//;

	  # remove unnecessary blanks
	  $val =~ s/^\s+//;
	  $val =~ s/\s+$//;

	  # ensure that CTYPE value is surrounded by apostrophes
	  if ( uc($key) =~ 'CTYPE' &&
	       $val !~ /^'.*'$/ )
	  {
	    $wcs .= uc($key) . " '$val'\n"
	  }
	  else
	  {
	    $wcs .= uc($key) . " $val\n"
	  }
	}

	$self->Set( "wcs $what", $wcs );
      }

      # turn array into string
      elsif ( 'ARRAY' eq ref $buf )
      {
	my $wcs = join( "\n", @$buf ) . "\n";
	$self->Set( "wcs $what", $wcs );
      }

      else
      {
	croak( __PACKAGE__, 
	       "->wcs($what): don't understand the last argument\n" );
      }
    }

    # must be a file name
    else
    {
      $self->Set( "wcs $what $buf" );
    }
  }


  # nothing left to do but croak
  else
  {
    croak( __PACKAGE__, "->wcs: unknown command `$what'\n" );
  }

}

#####################################################################

sub pan
{
  my $self = shift;
  my $what = shift;
  
  unless ( defined $what )
  {
    my %results = $self->_Get( "pan", 
			     { chomp => 1, res_wanthash => 1 } );
    
    for my $res ( values %results )
    {
      $res->{buf} = _splitbuf( $res->{buf} );
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
  
  unless ( $what eq 'abs' || $what eq 'rel' )
  {
    push @_, $what;
    $what = 'abs';
  }
  
  my ( @coords ) = @_;
  croak( __PACKAGE__, "->pan: not enough arguments\n" )
    unless @coords >= 2;
  
  croak( __PACKAGE__, "->pan: too many arguments\n" )
    unless @coords <= 3;
  
  croak( __PACKAGE__, "->pan: unknown coordinate system `$coords[2]'\n" )
    if @coords == 3 && !$Coords{$coords[3]};
  
  $self->Set( join(' ', 'pan', $what eq 'abs' ? 'to' : (), @coords ) );
}

#####################################################################

sub zoom
{
  my $self = shift;
  my $what = shift;

  unless ( defined $what )
  {
    return $self->_Get( 'zoom', 
		     { chomp => 1, res_wanthash => wantarray() } );
  }

  elsif ( 'abs' eq $what )
  {
    $what = shift;
    croak( __PACKAGE__, "->zoom: not enough arguments\n" )
      unless defined $what;
    $self->Set( "zoom to $what" );
  }

  elsif ( 'rel' eq $what )
  {
    $what = shift;
    croak( __PACKAGE__, "->zoom: not enough arguments\n" )
      unless defined $what;
    $self->Set( "zoom $what" );
  }

  elsif ( 0 == $what )
  {
    $self->Set( "zoom to fit" );
  }

  else
  {
    croak( __PACKAGE__, "->zoom: too many arguments\n" )
      if @_;
    $self->Set( "zoom to $what" );
  }
}


#####################################################################

use constant V_info      => 'info';
use constant V_panner    => 'panner';
use constant V_magnifier => 'magnifier';
use constant V_buttons   => 'buttons';
use constant V_colorbar  => 'colorbar';
use constant V_horzgraph => 'horzgraph';
use constant V_vertgraph => 'vertgraph';
use constant V_wcs       => 'wcs';
use constant V_detector  => 'detector';
use constant V_amplifier => 'amplifier';
use constant V_physical  => 'physical';
use constant V_image     => 'image';

BEGIN 
{ 
  my @symbols = qw( V_info V_panner V_magnifier V_buttons V_colorbar
		 V_horzgraph V_vertgraph V_wcs V_detector V_amplifier
		 V_physical V_image );

  $EXPORT_TAGS{view} = \@symbols;

  my %Element = map { $_, 1 } 
       ( V_info, V_panner, V_magnifier, V_buttons, V_colorbar,
	 V_horzgraph, V_vertgraph, V_wcs, V_detector, V_amplifier,
	 V_physical, V_image );
  
  sub view 
  { my ( $self, $element, $state ) = @_;
    
    croak( __PACKAGE__, "->view: unknown element `$element'\n" )
      unless exists $Element{$element};
    
    unless ( defined $state )
    {
      return str2bool($self->_Get( "view $element" ,
			{chomp => 1, res_wanthash => wantarray() } ));
    }
    
    else
    {
      $state = bool2str(str2bool($state));
      $self->Set( "view $element $state" );
    }
  }
}

#####################################################################

sub Set
{
  my ( $self, $cmd, $buf ) = @_;

  print STDERR ( __PACKAGE__, "->Set: $cmd\n" )
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
    croak( __PACKAGE__, ": error sending data to server" );
  }

  if ( keys %res < $self->{min_servers} )
  {
    $self->{res} = \%res;
    croak( __PACKAGE__, ": fewer than ", $self->{min_servers}, 
	   " server(s) responded" )
  }
}

#####################################################################

# wrapper for Get for use by outsiders
# set res_wanthash according to scalar or array mode
sub Get
{
  my $self = shift;
  my $cmd = shift;
  $self->_Get( $cmd, { res_wanthash => wantarray() } );
}


#####################################################################

# send an XPA Get request to the servers. 
# the passed attr hash modifies the returns; currently

# res_wanthash attribute: 
# _Get returns the XPA Get return hash directly if true, else it
# returns the {buf} entry from an arbitrary server.  if there's but
# one server, res_wanthash=0 makes for cleaner coding.

# chomp attribute: removes trailing newline from returned data

sub _Get
{
  my ( $self, $cmd, $attr ) = @_;

  print STDERR ( __PACKAGE__, "->_Get: $cmd\n" )
    if $self->{verbose};

  my %attr = ( $attr ? %$attr : () );

  $attr{res_wanthash} = $self->{res_wanthash} 
    unless defined $attr{res_wanthash};

  my %res = $self->{xpa}->Get( $self->{Server}, $cmd, 
			       $self->{xpa_attrs} );

  # chomp results
  $attr{chomp} ||= 0;
  foreach my $res ( values %res )
  {
    chomp $res->{message} if exists $res->{message};
    chomp $res->{buf} if exists $res->{buf} && $attr{chomp};
  }

  if ( grep { defined $_->{message} } values %res )
  {
    $self->{res} = \%res;
    croak( __PACKAGE__, ": error sending data to server" );
  }
  
  if ( keys %res < $self->{min_servers} )
  {
    $self->{res} = \%res;
    croak( __PACKAGE__, ": fewer than ", $self->{min_servers},
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

sub _splitbuf
{
  my $buf = shift;
  $buf =~ s/^\s+//;
  $buf =~ s/\s+$//;
  [ split( / /, $buf ) ]
}


#####################################################################

sub str2bool
{
  my $string = lc shift;

  $string eq 'yes' or $string eq 'on' or $string eq '1';
}

#####################################################################

sub bool2str
{
  my $bool = shift;
  $bool ? 'yes' : 'no';
}

#####################################################################


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
then apply its methods.  It is possible to both address more
than one B<DS9> with a single object, as well as having
multiple B<Image::DS9> objects communicate with their own
B<DS9> invocations.  Eventually there will be documentation
spelling out how to do this.


=head1 METHODS

The methods in this class closely follow the XPA access points.  The
documentation here tries to cover the mechanics of calling the
methods. For more information on what the methods do, or how the
arguments affect things, please consult the B<DS9> documentation.

=head2 Arguments

Commands sent to DS9 are sent as strings.  To prevent typos (and other
unwanted sideeffects) B<Image::DS9> makes many of the commands and
subcommands available as Perl constants -- mistype these and the
compiler will complain, not B<DS9>.  The complete set of constants
is indexed in L</Constants>.

=head2 Boolean values

Some methods take boolean values; these may be the strings C<on>, C<off>,
C<yes>, C<no>, or the integers C<1> or C<0>.  There are predifined
constants available for these:

	ON	=> 'on'
	OFF	=> 'off'
	YES	=> 'yes'
	NO	=> 'no'

=head2 Return Values

Because a single B<Image::DS9> object may communicate with multiple
instances of B<DS9>, queries may return more than one value.  
Because one usually communicates with a single B<DS9> instance,
if a query is made in scalar mode, the result is returned as a scalar,
i.e.:

	$cmap = $dsp->colormap();

In this mode, if more than one server responds, you'll get the
results for a randomly chosen server.

When queries are made in list mode, the return values are hashes,
rather than scalars.  The hash has as keys the names of the servers,
with the values being references to hashes with the keys C<name>,
C<buf> and C<message>.  The C<message> element is present if there was
an error.

The C<buf> element contains the results of a query. Ordinarily, the
C<buf> element will be unaltered (except for the removal of trailing
newlines) from what B<DS9> outputs.  Some methods, however, such as
B<bin()> will reformulate C<buf> to make life easier.

For example,

	use Data::Dumper;
	%colormaps = $dsp->colormap;
	print Dumper \%colormaps;

yields

	$VAR1 = {
	         'DS9:ds9 838e2ab4:32832' =>
	          {
	            'name' => 'DS9:ds9 838e2ab4:32832',
	            'buf' => 'Grey'
	          }
	        };

Sending data usually doesn't result in a return:

	$dsp->colormap( 'Grey' );


=head2 Error Returns

In case of error, an exception is thrown via B<croak()>.  The B<res()>
method will return a hash, keyed off of the servers' names.  For each
server which had an error, the hash value will be a reference to a
hash containing the keys C<name> and C<message>; the latter will
contain error information.  For those commands which return data, and
for those servers which did not have an error, the C<buf> key will be
available.

=head2 Administrative Methods

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

=item WaitTimeOut

The default number of seconds that the B<wait()> method should
try to contact B<DS9> servers.

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


=item wait

  $dsp->wait();
  $dsp->wait($timeout);

Try to contact the B<DS9> servers, and wait until at least
B<min_servers> have replied.  It will attempt this for
B<WaitTimeOut> seconds if no timeout is supplied, else
the given time.  It returns true upon success.  This routine
is useful for doing things like:

  $dsp = new Image::DS9;
  unless ( $dsp->nservers )
  {
    system("ds9 &" );
    $dsp->wait() or die( "unable to connect to DS9\n" );
  }

=back


=head2 Control Methods

=over 8

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

=item bin

  $dsp->bin( $attr, [$attr_value, $attr_value] );
  $dsp->bin( B_to_fit );
  $attr_state = $dsp->bin( $attr );

This sets the attributes for binning of FITS bin tables.  Constants for
the attributes are available (importable by the C<bin> tag, see
L</Constants>):

	B_about      => 'about'
	B_buffersize => 'buffersize'
	B_cols       => 'cols'
	B_factor     => 'factor'
	B_filter     => 'filter'
	B_function   => 'function'
	B_average    => 'average'
	B_sum        => 'sum'
	B_to_fit     => 'to fit'

All of the attributes, except the C<to fit> one, take one or more
arguments (see the B<DS9> documentation for what they are).  One can
query the value of the attributes, except for C<to fit> (which cannot
be queried), by passing no arguments.

If an attribute is multi-valued, a query yields a reference to an array,
not a scalar.  For instance:

	$res = $dsp->bin( B_about );
	($x, $y ) = @$res;

returns a reference to an array, while

	$res = $dsp->bin( B_buffersize );

returns a scalar.  Don't attempt to do

	($x, $y ) = $dsp->bin( B_about ); # ERROR DON"T DO THIS

As it will return a full blown hash as documented in L</Return Values>.

Queries called in list mode return results slightly different than
documented in L</Return Values>.  The C<buf> element is left as a
scalar for a single valued attribute, but is turned into a reference
to an array for a multivalued attribute.

=item colormap

  $dsp->colormap( $colormap );
  $colormap = $dsp->colormap;

  $dsp->colormap( CM_invert, $state );
  $invert = $dsp->colormap( CM_invert );


The first form sets the colormap. The argument should be the name of a
colormap (case is not important).  If no argument is specified, the
current colormap is returned.

In the second form the colormap can be inverted (or de-inverted).
C<$state> is a boolean.  If no state is specified, it returns the
current inversion state.

The following constants, importable via the C<colormap> tag, are
available (see L</Constants>:

	CM_invert	=> 'invert'

=item crosshair

  $dsp->crosshair( $x, $y [, $coord_system] );
  $coords = $dsp->crosshair( [$coord_system] );
  ($x, $y ) = @$coords

Manipulate or query the position of the crosshair.  Available values
for the coordinate system are (as constants, importable by the
C<coord> tag):

	Coord_fk4      => 'fk4'
	Coord_fk5      => 'fk5'
	Coord_icrs     => 'icrs'
	Coord_galactic => 'galactic'
	Coord_ecliptic => 'ecliptic'
	Coord_linear   => 'linear'
	Coord_image    => 'image'
	Coord_physical => 'physical'

To query the position, pass no coordinates to the method.  In scalar
mode, a query will return a reference to an array.  In list mode,
it will return a hash, slightly modified from that described in
the C</Return Value> section.  The C<buf> entries will be references
to arrays.

=item cursor

  $dsp->cursor( $x, $y );

Set the cursor position to the given position.

=item display

  $dsp->display( $state );
  %displays = $dsp->display;

If an argument is specified, this call will change how the data are
displayed.

The available display states are available as constants, importable
via the C<display> tag (see L</Constants>).  The available
constants and their values are:

	D_tile   => 'tile'
	D_single => 'single'
	D_blink  => 'blink'


If no argument is specified, the current display state is returned.
The state is will be returned as a string equivalent to the constants
C<D_blink>, C<D_tile> or C<D_single>.  For instance:

  my $ds9 = new DS9( { max_servers => 1 } );

  print "We're blinking!\n" if D_blink eq $ds9->display;



=item file

  $dsp->file( $file );
  $dsp->file( $file, $type );
  %files = $dsp->file;

Display the specified C<$file>. 
If called without a value, it will return the current file name loaded
for the current frame.

The file type is optional. The available file types are available as
constants, importable by the C<filetype> tag (see L</Constants>).  The
available constants and their values are:

	FT_MosaicImage	=> 'mosaicimage'
	FT_MosaicImages	=> 'mosaicimages'
	FT_Mosaic	=> 'mosaic'
	FT_Array	=> 'array'
	FT_Save		=> 'save'

The C<save> type is a bit of a misnomer; it causes the current frame
to be saved as a FITS image with the name given by C<$file>.

=item frame

  # get current frame(s) for server(s)
  $frame = $dsp->frame;
  @frames = $dsp->frame;

  # get list of frames for server(s)
  $frame_list = $dsp->frame( FR_all );
  @frame_list = $dsp->frame( FR_all );

  # perform a frame operation with no arguments
  $dsp->frame( $frame_op );

  # show the specified frame ($frame may be FR_all)
  $dsp->frame( show => $frame );

  # hide the current frame
  $dsp->frame( FR_hide );

  # show the specified frame ($frame may be FR_all)
  $dsp->frame( FR_hide => $frame );

  # delete the current frame
  $dsp->frame( FR_delete );
    
  # delete the specified frame  ($frame may be FR_all)
  $dsp->frame( delete => $frame );

  # delete all of the frames
  $dsp->frame( delete => FR_all );

Command B<DS9> to do frame operations.  Frame operations are nominally
strings.  As B<DS9> will interpret any string which isn't a frame
operation as the name of frame to switch to (or create, if necessary),
it's a really good idea to use the provided constants, importable by
the C<frame> tag, for the standard operations to prevent typos (see
L</Constants>).  The available frame constants and their values are:

	FR_active  => 'active'
	FR_all	   => 'all'
	FR_center  => 'center'
	FR_clear   => 'clear'
	FR_delete  => 'delete'
	FR_first   => 'first'
	FR_hide    => 'hide'
	FR_last    => 'last'
	FR_new     => 'new'
	FR_next    => 'next'
	FR_prev    => 'prev'
	FR_refresh => 'refresh'
	FR_reset   => 'reset'
	FR_show    => 'show'


To load a particular frame, specify the frame name as the operator.

To show a frame which has been hidden, use the second form with
the C<show> operator.

For example,

	$dsp->frame( FR_new );		# create a new frame
	$dsp->frame( '3' );		# load frame 3
	$dsp->frame( FR_hide );		# hide the current frame
	$dsp->frame( show => 3 );	# show frame 3
	$dsp->frame( FR_delete );	# delete the current frame

If B<frame()> is called with no arguments, it returns a list of the
current frames for all instances of B<DS9>.  If it is called with the
argument C<FR_all>, it returns a list of all of the frames.  In scalar
mode, this results in it returning a reference to an array containing
the frame ids. In list mode, it returns the standard hash as
documented in L</Return Values>, where the C<buf> element is now a
reference to an array containing the frame ids.

=item iconify

  $dsp->iconify($bool);
  $iconify_state = $dsp->iconify;

With a boolean argument, specify the iconification state, else
return it.

=item lower

  $dsp->lower();

Lowers the B<DS9> window in the stacking order

=item mode

  $mode = $dsp->mode;
  $dsp->mode( $state );

Change (or query) the first mouse button mode state.  Predefined
constants are available, importable via the C<mode> tag (see L</Constants>).
The available constants and their values are:

	MB_pointer	=> 'pointer'
	MB_crosshair	=> 'crosshair'
	MB_colorbar	=> 'colorbar'
	MB_pan		=> 'pan'
	MB_zoom		=> 'zoom'
	MB_rotate	=> 'rotate'
	MB_examine	=> 'examine'


=item orient

  $state = $dsp->orient;
  $dsp->orient( $state );

Change (or query) the orientation of the current frame. Predefined
states are available,  importable via the C<orient> tag; see L</Constants>.
The available constants and their values are:

	OR_X	=> 'x'
	OR_Y	=> 'y'
	OR_XY	=> 'xy'

=item pan

  # get current pan value(s) for server(s)
  $pan = $dsp->pan;
  @pan = $dsp->pan;

  # absolute pan
  $dsp->pan( abs => $x, $y, [$coord] );
  $dsp->pan( $x, $y, [ $coord ] );

  # relative pan
  $dsp->pan( rel => $x, $y, [$coord] );

This changes the pan position for the current frame.  Available values
for the coordinate system are (as constants, importable by the
C<coord> tag):

	Coord_fk4      => 'fk4'
	Coord_fk5      => 'fk5'
	Coord_icrs     => 'icrs'
	Coord_galactic => 'galactic'
	Coord_ecliptic => 'ecliptic'
	Coord_linear   => 'linear'
	Coord_image    => 'image'
	Coord_physical => 'physical'

To query the pan position, pass no coordinates to the method.  In
scalar mode, a query will return a reference to an array containing
the positions.  In list mode, it will return a hash, slightly modified
from that described in the C</Return Value> section.  The C<buf>
entries will be references to arrays.

=item raise

  $dsp->raise()

Raise the B<DS9> window in the windkow stacking order.

=item regions

This sets or queries regions. All of the constants mentioned below
which share the prefix C<Rg> are importable via the C<regions> tag.
See L</Constants> for a concise list.

To query the current list of regions and receive the results using
the current attribute formats,

  $regions = $dsp->regions();

The structure of the returned data is described below in the
discussion of the C<Rg_return_fmt> attribute.

To change the current attribute formats, use the following call:

  $dsp->regions( <attribute>, <format> );

The following attributes are available:

=over 8 

=item C<Rg_format> (or C<format> )

This governs which program the regions will be compatible with,
and is one of the following

	Rg_ds9         => 'ds9'
	Rg_saotng      => 'saotng'
	Rg_saoimage    => 'saoimage'
	Rg_pros        => 'pros'


=item C<Rg_coord> (or C<coord>)

This specifies the WCS coordinate system, and may be one of


	Coord_fk4      => 'fk4'
	Coord_fk5      => 'fk5'
	Coord_icrs     => 'icrs'
	Coord_galactic => 'galactic'
	Coord_ecliptic => 'ecliptic'
	Coord_linear   => 'linear'
	Coord_image    => 'image'
	Coord_physical => 'physical'

(constants importable via the C<coords> tag).

=item C<Rg_coordformat> or C<coordformat>

This specifies the format for the output coordinates, and may be
one of

	CoordFmt_degrees     => 'degrees'
	CoordFmt_sexagesimal => 'sexagesimal'

(constants importable via the C<coord_fmts> tag).

=item C<Rg_delim> or C<delim>

This specifies how regions should be separated, and may be one
of 

	Rg_nl          => 'nl
	Rg_semicolon   => 'semicolon'


=item C<Rg_return_fmt>

This specifies the structure of the data that a query returns.  If the
query was done in scalar mode, the data are returned directly in on of
the forms specified below. in list mode, the data are returned as
specified in L</Return Values>, but with the C<buf> element in the
forms below.

This attribute may have the following values.

=over 8

=item Rg_raw

The results are returned in exactly the form that B<DS9> sent them.
This is the default.

=back

=back

For example,

  $dsp->regions( Rg_delim, Rg_nl );
  $dsp->regions( Rg_format, Rg_ds9 );


Alternatively, one can request a different attribute format directly
in the query, but passing a hash reference:

  %attr = ( Rg_format, Rg_saotng,
	       Rg_coord, Coord_fk5,
               Rg_coordformat, Coord_sexagesimal );

  $regions = $dsp->regions( \%attr );


To add regions from a file, use the C<Rg_file> or C<Rg_load> tags:

  $dsp->regions( Rg_file, $file );

To save regions to a file, use the C<Rg_save> tag:

  $dsp->regions( Rg_save, $file );

To add a region in a Perl variable, pass a reference to the variable:

  $region = "circle 100 100 20";
  $dsp->regions( \$region );

(Yes, this is kludgy, but if it were passed in directly, it couldn't
be distinguished from a non region command, and error checking would be
impossible)

To change the selection state of the regions:

  $dsp->regions( Rg_selectall );
  $dsp->regions( Rg_selectnone );

To delete all of the regions:

  $dsp->regions( Rg_deleteall );

To change the stacking order of the currently selected region,

  $dsp->regions( Rg_moveback );
  $dsp->regions( Rg_movefront );

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

  %res = $dsp->res;

In case of error, the returned results from the failing B<XPA> call
are available via this method.  It returns a hash, keyed off of the
server signature(s). See the B<IPC::XPA> documentation for more
information on what the hashes contain.


=item scale

The scale method has a variety of calling sequences.  Various
constants are available, importable via the C<scale> tag; see
L</Constants>.

To specify or query the algorithm:

  $dsp->scale( $algorithm );
  $scale = $dsp->scale;

The C<$algorithm> constants and their values are

	S_linear   => 'linear'
	S_log	   => 'log'
	S_squared  => 'squared'
	S_sqrt     => 'sqrt'

The method of determining the data limits is set or queried via

  $dsp->scale( mode => $mode );
  $mode = $dsp->scale( S_mode );

The C<$mode> constants are

	S_minmax   => 'minmax'
	S_zscale   => 'zscale'
	S_user     => 'user'

User limits are set or queried via

  $dsp->scale( limits => [ $min, $max ] );
  $limits = $dsp->scale( S_limits );
  ($min, $max) = @$limits;

Since there are two limit values, querying the limits in a scalar
context returns a reference to an array.  In list mode, it returns
a hash slightly modified from that described in L</Return Values>.
The C<buf> elements are converted to array references.

To specify (or query) whether limits are applied to one or all of the
images in a mosaic, do this:

  $dsp->scale( scope => $scope );
  $scope = $dsp->scale( S_scope );

The C<$scope> constants are

	S_local    => 'local'
	S_global   => 'global'

The scale subparameters (C<limits>, C<mode>, C<scope>) are also
available as constants:

	S_limits   => 'limits'
	S_mode     => 'mode'
	S_scope    => 'scope'

Note however that using Perl constants to the left of the C<=E<gt>>
operator causes Perl to try and convert it into a string, i.e.

	$dsp->scale( S_mode => S_user )

is converted to

	$dsp->scale( 'S_mode', 'user' )

which isn't quite what you want.  Either of these

	$dsp->scale( S_mode, S_user )
	$dsp->scale( S_mode() => S_user )

does the trick.

Finally, to indicate whether only the data section of the image is
to be displayed, use C<S_datasec>, with a boolean value:

	$dsp->scale( S_datasec, ON );
        $datasec = $dsp->scale( S_datasec );


=item tile_mode

  # get the tile mode
  $mode = $dsp->tile_mode( );

  # set the tile mode
  $dsp->tile_mode( $mode );

  # get the grid mode attributes
  $attr = $dsp->tile_mode( T_grid, $attr );

  # set the grid mode attributes
  $dsp->tile_mode( T_grid, $attr, $arg1, ... );

Set (or get) the tiling mode.  This does B<not> switch into or out of
tile mode; use B<display()> to do that.  If called without a value, it
will return the current tiling mode.

Predefined constants for the modes, grid attributes, and grid mode are
available, importable via the C<tile> tag (see L</Constants>).  The
modes are:

	T_grid	 => 'grid'
	T_column => 'column'
	T_row	 => 'row'

The grid attributes are:

	T_gap	 => 'gap'
	T_layout => 'layout'
	T_mode	 => 'mode'

and the grid mode values are.

	T_auto	 => 'automatic'
	T_manual => 'manual'

The grid mode can be either of the above values,

  $dsp->tile_mode( T_grid, T_mode, T_auto );

The grid gap is a value in pixels:

  $dsp->tile_mode( T_grid, T_gap, $pixels );

and the grid layout requires the values for the rows and columns:

  $dsp->tile_mode( T_grid, T_layout, $row, $col );

Note that when getting the current grid layout parameter, it is
returned as a references to an array containing the row and column values.

=item view

  $view = $dsp->view( $element );
  $view = $dsp->view( $element, $state );

The first form returns the visibility of the element (as true or false).
The second sets the visibility of the element (as a boolean value).

  $dsp->view( V_buttons, 1 )
    unless $dsp->view( V_buttons );

The element names are available as constants, importable via the
C<view> tag (see L</Constants>).  The available constants and their
values are:

	V_info      => 'info'
	V_panner    => 'panner'
	V_magnifier => 'magnifier'
	V_buttons   => 'buttons'
	V_colorbar  => 'colorbar'
	V_horzgraph => 'horzgraph'
	V_vertgraph => 'vertgraph'
	V_wcs       => 'wcs'
	V_detector  => 'detector'
	V_amplifier => 'amplifier'
	V_physical  => 'physical'
	V_image     => 'image'

=item wcs

This is a complicated beast.  Please note that the query calls shown
are all done assuming a single B<DS9> server.  For multiple servers,
perform the queries in list mode (see L</Return Values>).

To set a particular WCS mapping or coordinate system, or determine
what the current one is:

  $dsp->wcs( $coord );
  $wcs = $dsp->wcs();

where C<$coord> is one of the following coordinate systems
(constants importable via the C<coords> tag, see L</Constants>)

	Coord_fk4      => 'fk4'
	Coord_fk5      => 'fk5'
	Coord_icrs     => 'icrs'
	Coord_galactic => 'galactic'
	Coord_ecliptic => 'ecliptic'
	Coord_linear   => 'linear'

Constants used below in the other C<wcs()> commands are importable
via the C<wcs> tag:

	WCS_align   => 'align'
	WCS_format  => 'format'
	WCS_reset   => 'reset'
	WCS_replace => 'replace'
	WCS_append  => 'append'

To align or de-align the image to equatorial WCS, or to determine the
current alignment state:

  $dsp->wcs( WCS_align, $bool );
  $align = $dsp->wcs( WCS_align );

To set the output format, or determine what it is:

  $dsp->wcs( WCS_format, $format );
  $format = $dsp->wcs( WCS_format );

where format is one of 

	CoordFmt_degrees     => 'degrees'
	CoordFmt_sexagesimal => 'sexagesimal'

(constants importable via C<coord_fmts> ).

To reset the WCS:

  $dsp->wcs( WCS_reset );

To replace or append to the WCS, using a B<DS9> compatible WCS record
in a file:

  $dsp->wcs( WCS_replace, $file );
  $dsp->wcs( WCS_append, $file );

To do the same, but with a WCS record in a Perl variable:

  $dsp->wcs( $wcs_action, \$wcs );
  $dsp->wcs( $wcs_action, \%wcs );
  $dsp->wcs( $wcs_action, \@wcs );

where C<$wcs_action> is either C<WCS_append> or C<WCS_replace>.  Note
that the second argument is a reference, to distinguish it from the
previous form which loads the WCS from a file.  If it is scalar
reference, the scalar should hold the WCS record.  If it is a hash
reference, a WCS record is constructed from the keys and values.  If
it is an array reference, the record is constructed by appending a
newline to each array value and concatenating the resultant strings.

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

=item Set

  $dsp->Set( $cmd, $buf )

Send an arbitrary XPA Set command to the DS9 server.  If there was an
error sending the command to the server, or fewer than expected
servers responded, it'll B<croak()>.  Messages from the server will be
made available via the B<res()> method.  See IPC::XPA for more
information on the format of those messages.

=item Get

  %results = $dsp->Get( $cmd )

Send an arbitrary XPA Get command to the DS9 Server.   If there was an
error sending the command to the server, or fewer than expected
servers responded, it'll B<croak()>.  Messages from the server will be
made available via the B<res()> method.

Upon success, it'll return the results of the command.  If called in
scalar mode, it'll return just one result (if there is more than one
server, it returns results from an arbitrary server). In array mode,
It'll return a hash, with the hash keys being the names of the server.
The hash values are themselves references to hashes containing
the results, with a key of C<buf>.

=back

=head1 Constants

Many constants have been defined to avoid typographic errors.  By default
they are not imported into the caller's namespace; they are available
via the Image::DS9 namespace, e.g. B<Image::DS9::CM_invert>.  Since
this is quite a mouthful, various import tags are available which
will import some, or all of the constants into the caller's namespace.
For example:

	use Image::DS9 qw( :frame :tile :filetype :display );

The following tags are available

	all
	bin
	colormap
	display
	filetype
	frame
	mode
	orient
	scale
	tile
	view


=over 8

=item all

This tag imports all of the symbols defined by the other tags, as
well as

	ON	=> 1
	OFF	=> 0
	YES	=> 'yes'
	NO	=> 'no'

=item bin

	B_about      => 'about'
	B_buffersize => 'buffersize'
	B_cols       => 'cols'
	B_factor     => 'factor'
	B_filter     => 'filter'
	B_function   => 'function'
	B_average    => 'average'
	B_sum        => 'sum'
	B_to_fit     => 'to fit'

=item colormap

	CM_invert    => 'invert'

=item coord_fmts

	CoordFmt_degrees     => 'degrees'
	CoordFmt_sexagesimal => 'sexagesimal'

=item coords

	Coord_fk4      => 'fk4'
	Coord_fk5      => 'fk5'
	Coord_icrs     => 'icrs'
	Coord_galactic => 'galactic'
	Coord_ecliptic => 'ecliptic'
	Coord_linear   => 'linear'
	Coord_image    => 'image'
	Coord_physical => 'physical'

=item display

	D_tile   => 'tile'
	D_single => 'single'
	D_blink  => 'blink'

=item file

	FT_MosaicImage	=> 'mosaicimage'
	FT_MosaicImages	=> 'mosaicimages'
	FT_Mosaic	=> 'mosaic'
	FT_Array	=> 'array'
	FT_Save		=> 'save'

=item frame

	FR_active  => 'active'
	FR_all	   => 'all'
	FR_center  => 'center'
	FR_clear   => 'clear'
	FR_delete  => 'delete'
	FR_first   => 'first'
	FR_hide    => 'hide'
	FR_last    => 'last'
	FR_new     => 'new'
	FR_next    => 'next'
	FR_prev    => 'prev'
	FR_refresh => 'refresh'
	FR_reset   => 'reset'
	FR_show    => 'show'

=item mode

	MB_pointer	=> 'pointer'
	MB_crosshair	=> 'crosshair'
	MB_colorbar	=> 'colorbar'
	MB_pan		=> 'pan'
	MB_zoom		=> 'zoom'
	MB_rotate	=> 'rotate'
	MB_examine	=> 'examine'

=item orient

	OR_X	=> 'x'
	OR_Y	=> 'y'
	OR_XY	=> 'xy'

=item regions

	Rg_movefront   => 'movefront'
	Rg_moveback    => 'moveback'
	Rg_selectall   => 'selectall'
	Rg_selectnone  => 'selectnone'
	Rg_deleteall   => 'deleteall'
	Rg_file        => 'file'
	Rg_load	       => 'load'
	Rg_save	       => 'save'

	Rg_format      => 'format'
	Rg_coord       => 'coord'
	Rg_coordformat => 'coordformat'
	Rg_delim       => 'delim'

	Rg_nl          => 'nl
	Rg_semicolon   => 'semicolon'

	Rg_ds9         => 'ds9'
	Rg_saotng      => 'saotng'
	Rg_saoimage    => 'saoimage'
	Rg_pros        => 'pros'

	Rg_return_fmt
	Rg_raw


=item scale


	S_linear   => 'linear'
	S_log	   => 'log'
	S_squared  => 'squared'
	S_sqrt     => 'sqrt'

	S_minmax   => 'minmax'
	S_zscale   => 'zscale'
	S_user     => 'user'

	S_local    => 'local'
	S_global   => 'global'

	S_limits   => 'limits'
	S_mode     => 'mode'
	S_scope    => 'scope'
        S_datasec  => 'datasec'

=item tile

	T_grid	 => 'grid'
	T_column => 'column'
	T_row	 => 'row'
	T_gap	 => 'gap'
	T_layout => 'layout'
	T_mode	 => 'mode'
	T_auto	 => 'automatic'
	T_manual => 'manual'


=item view

	V_info      => 'info'
	V_panner    => 'panner'
	V_magnifier => 'magnifier'
	V_buttons   => 'buttons'
	V_colorbar  => 'colorbar'
	V_horzgraph => 'horzgraph'
	V_vertgraph => 'vertgraph'
	V_wcs       => 'wcs'
	V_detector  => 'detector'
	V_amplifier => 'amplifier'
	V_physical  => 'physical'
	V_image     => 'image'

=item wcs

	WCS_align   => 'align'
	WCS_format  => 'format'
	WCS_reset   => 'reset'
	WCS_replace => 'replace'
	WCS_append  => 'append'

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
