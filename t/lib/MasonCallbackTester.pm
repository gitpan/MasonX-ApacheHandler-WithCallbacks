package MasonCallbackTester;

# $Id: MasonCallbackTester.pm,v 1.8 2003/02/14 22:43:02 david Exp $

use strict;
use MasonX::ApacheHandler::WithCallbacks;
use HTML::Mason::Exceptions;
use Apache;
use Apache::Constants qw(HTTP_OK);
use constant KEY => 'myCallbackTester';

sub simple {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} = 'Success';
}

my $url = 'http://example.com/';
sub redir {
    my $cbh = shift;
    my $val = $cbh->value;
    $cbh->redirect($url, $val);
}

sub set_status_ok {
    my $cbh = shift;
    $cbh->apache_req->status(HTTP_OK);
    $cbh->abort(HTTP_OK)
}

sub test_redirected {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} = $cbh->redirected eq $url ? 'yes' : 'no';
    $cbh->abort(HTTP_OK)
}

sub test_aborted {
    my $cbh = shift;
    my $args = $cbh->request_args;
    my $val = $cbh->value;
    eval { $cbh->abort(500)} if $val;
    $args->{result} = $cbh->aborted($@) ? 'yes' : 'no';
    $cbh->abort(HTTP_OK)
}

sub priority {
    my $cbh = shift;
    my $args = $cbh->request_args;
    my $val = $cbh->value;
    $val = '5' if $val eq 'def';
    $args->{result} .= " $val";
}

sub chk_priority {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} .= $cbh->priority;
}

sub chk_cb_key {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} .= $cbh->cb_key;
}

sub chk_pkg_key {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} .= $cbh->pkg_key;
}

sub chk_trig_key {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} .= $cbh->trigger_key;
}

sub multi {
    my $cbh = shift;
    my $args = $cbh->request_args;
    my $val = $cbh->value;
    $args->{result} = scalar @$val;
}

sub upperit {
    my $cbh = shift;
    my $args = $cbh->request_args;
    $args->{result} = uc $args->{result} if $args->{do_upper};
}

sub exception {
    my $cbh = shift;
    my $args = $cbh->request_args;
    if ($cbh->value) {
        # Throw an exception object.
        HTML::Mason::Exception->throw( error => "He's dead, Jim" );
    } else {
        # Just die.
        die "He's dead, Jim";
    }
}

#{ cb => $cb,
#  cb_key => $cb_key,
#  priority => $priority,
#  pkg_key => $pkg_key
#}

my $server = Apache->server;
my $cfg = $server->dir_config;
my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( comp_root => $cfg->{MasonCompRoot},
    data_dir => $cfg->{MasonDataDir},
    callbacks => [{ pkg_key => KEY,
                    cb_key  => 'simple',
                    cb      => \&simple
                  },
                  { pkg_key => KEY,
                    cb_key  => 'redir',
                    cb      => \&redir
                  },
                  { pkg_key => KEY,
                    cb_key  => 'set_status_ok',
                    cb      => \&set_status_ok
                  },
                  { pkg_key => KEY,
                    cb_key  => 'test_redirected',
                    cb      => \&test_redirected
                  },
                  { pkg_key => KEY,
                    cb_key  => 'test_aborted',
                    cb      => \&test_aborted
                  },
                  { pkg_key => KEY,
                    cb_key  => 'priority',
                    cb      => \&priority
                  },
                  { pkg_key => KEY,
                    cb_key  => 'multi',
                    cb      => \&multi
                  },
                  { pkg_key => KEY,
                    cb_key  => 'chk_priority',
                    cb      => \&chk_priority
                  },
                  { pkg_key => KEY,
                    cb_key  => 'cb_key1',
                    cb      => \&chk_cb_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'cb_key2',
                    cb      => \&chk_cb_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'cb_key3',
                    cb      => \&chk_cb_key
                  },
                  { pkg_key => KEY . '1',
                    cb_key  => 'pkg_key1',
                    cb      => \&chk_pkg_key
                  },
                  { pkg_key => KEY . '2',
                    cb_key  => 'pkg_key2',
                    cb      => \&chk_pkg_key
                  },
                  { pkg_key => KEY . '3',
                    cb_key  => 'pkg_key3',
                    cb      => \&chk_pkg_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'trig_key1',
                    cb      => \&chk_trig_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'trig_key2',
                    cb      => \&chk_trig_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'trig_key3',
                    cb      => \&chk_trig_key
                  },
                  { pkg_key => KEY,
                    cb_key  => 'exception',
                    cb      => \&exception
                  },
                 ],
    pre_callbacks => [\&upperit],
    post_callbacks => [\&upperit]
  );

sub handler { $ah->handle_request(@_)} ;

1;

__END__
