# ABSTRACT: Config role for Dancer2 core objects
package Dancer2::Core::Role::ConfigReader;
$Dancer2::Core::Role::ConfigReader::VERSION = '0.400000';
use Moo::Role;

use File::Spec;
use Config::Any;
use Hash::Merge::Simple;
use Carp 'croak';
use Module::Runtime 'require_module';

use Dancer2::Core::Factory;
use Dancer2::Core;
use Dancer2::Core::Types;
use Dancer2::FileUtils 'path';

with 'Dancer2::Core::Role::HasLocation';

has default_config => (
    is      => 'ro',
    isa     => HashRef,
    lazy    => 1,
    builder => '_build_default_config',
);

has config_location => (
    is      => 'ro',
    isa     => ReadableFilePath,
    lazy    => 1,
    default => sub { $ENV{DANCER_CONFDIR} || $_[0]->location },
);

# The type for this attribute is Str because we don't require
# an existing directory with configuration files for the
# environments.  An application without environments is still
# valid and works.
has environments_location => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    default => sub {
        $ENV{DANCER_ENVDIR}
          || File::Spec->catdir( $_[0]->config_location, 'environments' )
          || File::Spec->catdir( $_[0]->location,        'environments' );
    },
);

has config => (
    is      => 'ro',
    isa     => HashRef,
    lazy    => 1,
    builder => '_build_config',
);

has environment => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_environment',
);

has config_files => (
    is      => 'ro',
    lazy    => 1,
    isa     => ArrayRef,
    builder => '_build_config_files',
);

has local_triggers => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { +{} },
);

has global_triggers => (
    is      => 'ro',
    isa     => HashRef,
    default => sub {
        my $triggers = {
            traces => sub {
                my ( $self, $traces ) = @_;

                # Carp is already a dependency
                $Carp::Verbose = $traces ? 1 : 0;
            },
        };

        my $runner_config =
          defined $Dancer2::runner
          ? Dancer2->runner->config
          : {};

        for my $global ( keys %$runner_config ) {
            next if exists $triggers->{$global};
            $triggers->{$global} = sub {
                my ( $self, $value ) = @_;
                Dancer2->runner->config->{$global} = $value;
            }
        }

        return $triggers;
    },
);

sub _build_default_config { +{} }

sub _build_environment { 'development' }

use MF::Utils qw(listdir file);

sub _build_config_files {
    my @files =
      grep { $_ } map { file CONFIG => Web => "$_.yml", want => 'path' }
      ( 'config', $ENV{DANCER_ENVIRONMENT} );

    listdir $ENV{MF_CONFIG_DIR} => sub {
        my %row = @_;

        my $plugin = $row{plugin};

        return if $plugin eq 'Web';

        my $config_file = file CONFIG => $plugin => 'config.yml',
          want => 'path'
          or return;

        push @files, $config_file;
    } => {
        dir_only => 1,
        alias    => 'plugin',
    };

    return \@files;
}

sub _build_config {
    my ($self) = @_;

    my $location = $self->config_location;
    my $default  = $self->default_config;

    my $config = Hash::Merge::Simple->merge(
        $default,
        map {
            warn "Merging config file $_\n"
              if $ENV{DANCER_CONFIG_VERBOSE};
            $self->load_config_file($_)
        } @{ $self->config_files }
    );

    $config = $self->_normalize_config($config);
    return $config;
}

sub _set_config_entries {
    my ( $self, @args ) = @_;
    my $no = scalar @args;
    while (@args) {
        $self->_set_config_entry( shift(@args), shift(@args) );
    }
    return $no;
}

sub _set_config_entry {
    my ( $self, $name, $value ) = @_;

    $value = $self->_normalize_config_entry( $name, $value );
    $value = $self->_compile_config_entry( $name, $value, $self->config );
    $self->config->{$name} = $value;
}

sub _normalize_config {
    my ( $self, $config ) = @_;

    foreach my $key ( keys %{$config} ) {
        my $value = $config->{$key};
        $config->{$key} = $self->_normalize_config_entry( $key, $value );
    }
    return $config;
}

sub _compile_config {
    my ( $self, $config ) = @_;

    foreach my $key ( keys %{$config} ) {
        my $value = $config->{$key};
        $config->{$key} = $self->_compile_config_entry( $key, $value, $config );
    }
    return $config;
}

sub settings { shift->config }

sub setting {
    my $self = shift;
    my @args = @_;

    return ( scalar @args == 1 )
      ? $self->settings->{ $args[0] }
      : $self->_set_config_entries(@args);
}

sub has_setting {
    my ( $self, $name ) = @_;
    return exists $self->config->{$name};
}

sub load_config_file {
    my ( $self, $file ) = @_;
    my $config;

    eval {
        my @files = ($file);
        my $tmpconfig =
          Config::Any->load_files( { files => \@files, use_ext => 1 } )->[0];
        ( $file, $config ) = %{$tmpconfig} if defined $tmpconfig;
    };
    if ( my $err = $@ || ( !$config ) ) {
        croak "Unable to parse the configuration file: $file: $@";
    }

    # TODO handle mergeable entries
    return $config;
}

# private

my $_normalizers = {
    charset => sub {
        my ($charset) = @_;
        return $charset if !length( $charset || '' );

        require_module('Encode');
        my $encoding = Encode::find_encoding($charset);
        croak
"Charset defined in configuration is wrong : couldn't identify '$charset'"
          unless defined $encoding;
        my $name = $encoding->name;

        # Perl makes a distinction between the usual perl utf8, and the strict
        # utf8 charset. But we don't want to make this distinction
        $name = 'utf-8' if $name eq 'utf-8-strict';
        return $name;
    },
};

sub _normalize_config_entry {
    my ( $self, $name, $value ) = @_;
    $value = $_normalizers->{$name}->($value)
      if exists $_normalizers->{$name};
    return $value;
}

sub _compile_config_entry {
    my ( $self, $name, $value, $config ) = @_;

    my $trigger =
      exists $self->local_triggers->{$name}
      ? $self->local_triggers->{$name}
      : $self->global_triggers->{$name};

    defined $trigger or return $value;

    return $trigger->( $self, $value, $config );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dancer2::Core::Role::ConfigReader - Config role for Dancer2 core objects

=head1 VERSION

version 0.400000

=head1 DESCRIPTION

Provides a C<config> attribute that feeds itself by finding and parsing
configuration files.

Also provides a C<setting()> method which is supposed to be used by externals to
read/write config entries.

=head1 ATTRIBUTES

=head2 location

Absolute path to the directory where the server started.

=head2 config_location

Gets the location from the configuration. Same as C<< $object->location >>.

=head2 environments_location

Gets the directory were the environment files are stored.

=head2 config

Returns the whole configuration.

=head2 environments

Returns the name of the environment.

=head2 config_files

List of all the configuration files.

=head1 METHODS

=head2 settings

Alias for config. Equivalent to <<$object->config>>.

=head2 setting

Get or set an element from the configuration.

=head2 has_setting

Verifies that a key exists in the configuration.

=head2 load_config_file

Load the configuration files.

=head1 AUTHOR

Dancer Core Developers

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Alexis Sukrieh.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
