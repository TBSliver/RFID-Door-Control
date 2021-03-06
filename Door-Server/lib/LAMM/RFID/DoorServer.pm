package LAMM::RFID::DoorServer;
use Mojo::Base 'Mojolicious';

use LAMM::RFID::DoorServer::DB;

has schema => sub {
  my $c = shift;
  return LAMM::RFID::DoorServer::DB->connect(@{$c->config->{db}});
};

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->moniker('lamm_rfid_doorserver');

  push @{$self->app->commands->namespaces}, 'LAMM::RFID::DoorServer::Command';

  $self->plugin('Config');

  $self->plugin('Authentication', {
    autoload_user => 1,
    load_user => sub {
      my ( $c, $uid ) = @_;
      return $c->db->resultset('User')->find($uid);
    },
    validate_user => sub {
      my ( $c, $username, $password, $extra ) = @_;
      my $user_result = $c->db->resultset('User')->find({
          username => $username});
      $c->log->warn("User not found for username [$username]") and return unless defined $user_result;
      if ($user_result->check_password($password)) {
        $c->log->debug("Successful Authentication for user [$username]");
        return $user_result->id;
      }
      $c->log->warn("Failed Authentication for user [$username]");
      return;
    },
  });

  $self->helper( db => sub { $self->app->schema } );

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('root#index');
  $r->post('/login')->to('root#auth_login');
  $r->any('/logout')->to('root#auth_logout');

  my $admin = $r->under('/admin')->to('root#auth');
  $admin->get('/')->to('admin#index');
  for my $endpoint ( qw/ card door assign user / ) {
    $admin->any("/$endpoint/:action")->to("admin-$endpoint#");
  }

  my $api = $r->under('/api')->to('api#auth');

  $api->get('/')->to('api#index');
  $api->get('/fetch')->to('api#fetch');
}

1;
