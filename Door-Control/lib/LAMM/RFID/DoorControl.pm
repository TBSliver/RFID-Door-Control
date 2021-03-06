package LAMM::RFID::DoorControl;

use Moo;
use MooX::Options protect_argv => 0;
use aliased 'LAMM::RFID::DoorControl::Schema';
use aliased 'LAMM::RFID::DoorControl::Fetch';
use Config::Tiny;
use namespace::clean  -except => [qw/_options_data _options_config/];

option config_file => (
  is => 'lazy',
  format => 's',
  doc => "The config file to use",
  short => 'c',
  default => 'config.cfg',
);

has config => (
  is => 'lazy',
  builder => sub {
    my $self = shift;
    my $cfg = Config::Tiny->read( $self->config_file );
    return $cfg;
  },
);

has fetcher => (
  is => 'lazy',
  builder => sub {
    my $self = shift;
    return Fetch->new(
      endpoint => $self->config->{ 'fetch' }->{ 'endpoint' },
      door => $self->config->{ 'main' }->{ 'door' },
      key => $self->config->{ 'fetch' }->{ 'api_key' },
    );
  },
);

has schema => (
  is => 'lazy',
  builder => sub {
    my $self = shift;
    return Schema->connect(
      $self->config->{ 'db' }->{ 'dsn' },
      $self->config->{ 'db' }->{ 'username' },
      $self->config->{ 'db' }->{ 'password' },
    );
  },
);

sub cmd_deploy {
  my $self = shift;

  $self->schema->deploy;
}

sub cmd_update {
  my ( $self ) = @_;

  my $data = $self->fetcher->get;
  die "No data from endpoint, not updating!" unless defined $data;
  my $allowed_rs = $self->schema->resultset( 'AllowedCard' );

  my @all_rs = $allowed_rs->search(undef, { select => ['user_id'] })->all;
  my %to_remove = map { $_->user_id => 1 } @all_rs;

  for my $card ( @{ $data->{ allowed_card } } ) {
    $allowed_rs->update_or_create(
      {
        user_id => $card->{user_id},
        card_key => $card->{card_key},
      },
      { key => 'primary' },
    );
    delete $to_remove{ $card->{user_id} };
  }
  for (keys %to_remove) {
    my $not_found_rs = $allowed_rs->find( $_ );
    $not_found_rs->delete;
  }
}

sub BUILD {
  my ( $self ) = @_;

  my ( $cmd, @extra ) = @ARGV;

  die "Must supply a command\n" unless $cmd;
  die "Extra commands found - Please provide only one!\n" if @extra;
  die "No such command ${cmd} \n" unless $self->can("cmd_${cmd}");

  $self->${\"cmd_${cmd}"};
}

1;
