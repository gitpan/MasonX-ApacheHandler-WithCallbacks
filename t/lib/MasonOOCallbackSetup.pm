package MasonOOCallbackSetup;

use strict;
use MasonOOCallbackTester;
use MasonOOCallbackTesterSub;
use MasonOOCallbackTesterEmpty;
use MasonOOCallbackTesterReqSub;
use MasonX::ApacheHandler::WithCallbacks;

# This package handles the main test class (MasonOOCalbackTester) and one
# of its subclasses (MasonOOCallbackTesterSub).

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    cb_classes => [qw(OOTester OOTesterSub)]
  );

sub handler { $ah->handle_request(@_) }

##############################################################################
# This package handles an empty subclass, which is itself a subclass of
# MasonOOCallbackTesterSub.
package MasonOOCallbackEmpty;
use strict;

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    cb_classes => [qw(Empty)]
  );

sub handler { $ah->handle_request(@_) }

##############################################################################
# This package handles a subclass that overrides its parent's request callback
# methods, thus demonstrating that, yes, there is potentially a use for this.
package MasonOOCallbackSubReq;

use strict;

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    cb_classes => [qw(ReqSub)]
  );

sub handler { $ah->handle_request(@_) }

##############################################################################
# This package uses the special 'ALL' string for the cb_classes parameter to
# tell MasonX::CallbackHandler to tell MasonX::ApacheHandler::WithCallbacks
# about _all_ of its subclasses, thus including them all and all of their
# callback methods in the ApacheHandler object.
package MasonOOCallbackAll;

use strict;

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    cb_classes => 'ALL'
  );

sub handler { $ah->handle_request(@_) }

##############################################################################
# This package combines an OO callback class with a functional one, to make
# sure that anyone who is crazy enough to use both at once can do so.
package MasonOOCallbackCombined;
use MasonCallbackTester;
use strict;

sub presto {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} = 'PRESTO' if $args->{do_presto};
}

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    cb_classes => [qw(OOTester)],
    callbacks => [{ pkg_key => MasonCallbackTester->KEY,
                    cb_key  => 'simple',
                    cb      => \&MasonCallbackTester::simple
                  }],
    pre_callbacks  => [\&presto],
  );

sub handler { $ah->handle_request(@_) }

1;
__END__
