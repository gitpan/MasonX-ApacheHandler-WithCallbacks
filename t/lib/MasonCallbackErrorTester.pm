package MasonCallbackErrorTester;

# $Id: MasonCallbackErrorTester.pm,v 1.1 2003/02/14 22:43:02 david Exp $

use strict;
use MasonX::ApacheHandler::WithCallbacks;
use Apache;
use Apache::Constants qw(HTTP_OK);
use constant KEY => 'errorTester';

my $server = Apache->server;
my $cfg = $server->dir_config;

sub bad_cb_key_handler {
    my $ah = MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir},
        callbacks => [{ pkg_key => KEY,
                        cb_key  => '', # Ooops!
                        cb      => sub {}
                      }],
      );
    $ah->handle_request(@_);
}

sub bad_priority_handler {
    my $ah = MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir},
        callbacks => [{ pkg_key => KEY,
                        cb_key  => 'priority',
                        priority => 'foo', # Oops!
                        cb      => sub {}
                      }],
      );
    $ah->handle_request(@_);
}

sub bad_coderef_handler {
    my $ah = MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir},
        callbacks => [{ pkg_key => KEY,
                        cb_key  => 'coderef',
                        cb      => 'bogus' # Oops!
                      }],
      );
    $ah->handle_request(@_);
}

sub used_key_handler {
    my $ah = MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir},
        callbacks => [{ pkg_key => KEY,
                        cb_key  => 'my_key',
                        cb      => sub {}
                      },
                      { pkg_key => KEY,
                        cb_key  => 'my_key', # Oops!
                        cb      => sub {}
                      }],
      );
    $ah->handle_request(@_);
}

sub bad_global_coderef_handler {
    my $ah = MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir},
        pre_callbacks => ['foo'] # Ooops!
      );
    $ah->handle_request(@_);
}

sub no_cbs_handler {
    MasonX::ApacheHandler::WithCallbacks->new
      ( comp_root => $cfg->{MasonCompRoot},
        data_dir => $cfg->{MasonDataDir} );
}


1;

__END__
