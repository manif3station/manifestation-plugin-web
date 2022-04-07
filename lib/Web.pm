package Web;

use Dancer2 appname => 'Web';

use YAML qw(Load);
use JSON ();
use Readonly;

use MF::Services;
use MF::Utils qw(
  add_lib
  defor
  file
  folder
  listdir
  mf_envs
  template_file
);

my %env = mf_envs;

hook before_template_render => sub {
    my ($stash) = @_;
    $stash->{Services} = 'Services';
};

## ------------------
## Load Perl Modules
## ------------------
my @modules = ();

listdir $env{MF_LIB_DIR} => sub {
    my %row = @_;

    my %lib = folder LIB => $row{plugin}, '.';

    if ( $lib{status} eq 'stateful' ) {
        add_lib $lib{dirs}[0];
        add_lib $lib{dirs}[1];
    }
    else {
        add_lib $lib{folder};
    }

    my $route_module = file LIB => $row{plugin} => "Routes/$row{plugin}.pm",
      want => 'file'
      or return;

    push @modules, $route_module;
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
        $stash->{template_file}          = \&template_file;
        $stash->{form_data}              = \&form_data;
    }
};

sub form_data {
    my ( $store, $field ) = @_;
    return defor params->{$field}, $store->{$field};
}

listdir $env{MF_VIEWS_DIR} => sub {
    my %row = @_;

    my $header = template_file $row{plugin}, "layouts/header";

    push @HEADERS, $header if $header;

    my $footer = template_file $row{plugin}, "layouts/footer";

    push @FOOTERS, $footer if $footer;
} => {
    alias    => 'plugin',
    dir_only => 1,
};

1;
