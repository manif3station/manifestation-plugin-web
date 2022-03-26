package Web;

use Dancer2 appname => 'Web';

use YAML qw(Load);
use JSON ();
use Readonly;

use MF::Services;
use MF::Utils qw(
  add_lib
  listdir
  mf_envs
);

my %env = mf_envs;

hook before_template_render => sub {
    my ($stash) = @_;
    $stash->{plugin} = \&plugin;
};

## ------------------
## Load Perl Modules
## ------------------
my @modules = ();

listdir $env{MF_LIB_DIR} => sub {
    my %row = @_;

    add_lib my $lib = $row{path};

    push @modules, "Routes/$row{plugin}.pm"
      if -f "$lib/Routes/$row{plugin}.pm";
  },
  {
    alias    => 'plugin',
    dir_only => 1,
  };

foreach my $pmfile (@modules) {
    require $pmfile;
    print "Loaded Module: $pmfile\n"
      if $ENV{DEV};
}

## -------------
## Load Configs
## -------------
if ( $ENV{DEV} ) {
    printf STDERR "%s\n", ( "-" x 80 );
    printf STDERR "Site Config: %s\n",
      JSON->new->pretty->canonical->encode( config() );
    printf STDERR "%s\n", ( "-" x 80 );
}

## -----------------------
## Load Header and Footer
## ----------------------
my ( @HEADERS, @FOOTERS );

hook before_template_render => {
    Web => sub {
        my ($stash) = @_;
        $stash->{include_plugin_headers} = \@HEADERS;
        $stash->{include_plugin_footers} = \@FOOTERS;
        $stash->{form_data} = \&form_data;
    }
};

sub form_data {
    my ($store, $field) = @_;
    return params->{$field} // $store->{$field};
}

listdir $env{MF_VIEWS_DIR} => sub {
    my %row = @_;

    next if !-d ( my $dir = "$row{path}/layouts" );

    push @HEADERS, "$row{plugin}/layouts/header.tt"
      if -f "$dir/header.tt";

    push @FOOTERS, "$row{plugin}/layouts/footer.tt"
      if -f "$dir/footer.tt";
  },
  {
    alias    => 'plugin',
    dir_only => 1,
  };

1;
