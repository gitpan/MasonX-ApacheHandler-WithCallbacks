# $Id: 04conf.t,v 1.1 2003/06/15 22:36:57 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catdir);
use lib 'lib', catdir('t', 'lib');
use LWP::UserAgent;
use Apache::test qw(have_httpd);

##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
unless (-e catdir('t', 'httpd.conf') and -x catdir('t', 'httpd')) {
    # Skip all of the tests.
    plan skip_all => 'no httpd';
} elsif ($] < 5.006) {
    # No OO interface before Perl 5.6. Skip all of the tests and exit.
    plan skip_all => 'OO interface not supported prior to Perl 5.6.0';
} else {
    plan tests => 8;
}

sub run_test {
    my ($uri, $test_name, $code, $expect) = @_;
    my $res = Apache::test->fetch($uri);
    is( $res->code, $code, "$test_name for $code code" );
    is( $res->content, $expect, "Check $test_name for '$expect'" )
}

# Test MasonCallbacks + MasonDefaultPkgKey.
run_test '/conf_test/test.html?CBFoo|pkg_key_cb=1',
  "Testd MasonCallbacks + MasonDefaultPkgKey",
  200,
  'CBFoo';

# Test MasonCallbacks + MasonDefaultPriority.
run_test '/conf_test/test.html?CBFoo|priority_cb=1',
  "Test MasonCallbacks + MasonDefaultPriority.",
  200,
  '3';

# Test MasonPreCallbacks.
run_test '/conf_test/test.html?result=success&do_upper=1',
  "Test MasonPreCallback",
  200,
  'SUCCESS';

# Test MasonPostCallbacks.
run_test '/conf_test/test.html?result=SUCCESS&do_lower=1',
  "Test MasonPreCallback",
  200,
  'success';
