# $Id: 04conf.t,v 1.2 2003/06/17 22:43:04 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catdir);
use Apache::Test qw(have_lwp);
use Apache::TestRequest qw(GET POST);

plan tests => 8, have_lwp;

sub run_test {
    my ($uri, $test_name, $code, $expect) = @_;
    my $res = GET $uri;
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
