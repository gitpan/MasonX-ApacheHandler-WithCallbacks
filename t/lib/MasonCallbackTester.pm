package MasonCallbackTester;

# $Id: MasonCallbackTester.pm,v 1.4 2003/01/16 07:10:51 david Exp $

use strict;
use MasonX::ApacheHandler::WithCallbacks;
use Apache;
use Apache::Constants qw(HTTP_OK);
use constant KEY => 'myCallbackTester';

sub simple {
    my ($cbh, $args, $val, $key) = @_;
    $args->{result} = 'Success';
}

my $url = 'http://example.com/';
sub redir {
    my ($cbh, $args, $val, $key) = @_;
    $cbh->redirect($url, $val);
}

sub set_status_ok {
    my $cbh = shift;
    $cbh->apache_req->status(HTTP_OK);
    $cbh->abort(HTTP_OK)
}

sub test_redirected {
    my ($cbh, $args, $val, $key) = @_;
    $args->{result} = $cbh->redirected eq $url ? 'yes' : 'no';
    $cbh->abort(HTTP_OK)
}

sub test_aborted {
    my ($cbh, $args, $val, $key) = @_;
    eval { $cbh->abort(500)} if $val;
    $args->{result} = $cbh->aborted($@) ? 'yes' : 'no';
    $cbh->abort(HTTP_OK)
}

sub priority {
    my ($cbh, $args, $val, $key) = @_;
    $val = '5' if $val eq 'def';
    $args->{result} .= " $val";
}

sub multi {
    my ($cbh, $args, $val, $key) = @_;
    $args->{result} = scalar @$val;
}

sub upperit {
    my ($cbh, $args) = @_;
    $args->{result} = uc $args->{result} if $args->{do_upper};
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
                 ],
    pre_callbacks => [\&upperit],
    post_callbacks => [\&upperit]
  );

sub handler { $ah->handle_request(@_)} ;

1;

__END__
