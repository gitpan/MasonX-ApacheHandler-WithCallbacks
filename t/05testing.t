# $Id: 05testing.t,v 1.1 2003/06/15 22:36:57 david Exp $

# Set up the Apache package just for our own tests.
package Apache;
sub server { bless {}, __PACKAGE__ }
sub dir_config {}

##############################################################################
# Now, on to business!

package main;
use strict;
use Test::More tests => 8;
use File::Spec::Functions qw(catdir);
use lib 'lib', catdir('t', 'lib');
use MasonX::CallbackTester;
use MasonCallbackTester;
use MasonOOCallbackTester;

my $ah = MasonX::ApacheHandler::WithCallbacks->new;
my $apache_req = Apache::FakeRequest->new;
my @args = ( request_args => {},
             apache_req   => $apache_req,
             ah           => $ah,
             priority     => 4,
             pkg_key      => 'ToTest',
             value        => 1,
           );


##############################################################################
# Test some of the functional callbacks, first.
my $cbh = MasonX::CallbackHandler->new(@args);
MasonCallbackTester::simple($cbh);
is( $cbh->request_args->{result}, 'Success', "Check for success!" );

# Try the redirect callback.
$cbh = MasonX::CallbackHandler->new(@args);
MasonCallbackTester::redir($cbh);
ok( $cbh->redirected, "Check that it redirected" );

# Have the redirect abort.
$cbh = MasonX::CallbackHandler->new(@args, value => 0);
eval {  MasonCallbackTester::redir($cbh) };
ok( $cbh->aborted, "Check that it aborted" );
ok( $cbh->redirected, "Check that it redirected" );

##############################################################################
# Now test some of the OO methods.
$cbh = MasonOOCallbackTester->new(@args);
$cbh->simple;
is( $cbh->request_args->{result}, 'Simple Success', "Check for OO success!" );

# Try the redirect callback.
$cbh = MasonOOCallbackTester->new(@args);
$cbh->redir;
ok( $cbh->redirected, "Check that it redirected" );

# Have the redirect abort.
$cbh = MasonOOCallbackTester->new(@args, value => 0);
eval {  $cbh->redir };
ok( $cbh->aborted, "Check that it aborted" );
ok( $cbh->redirected, "Check that it redirected" );



__END__

my $to_test = MasonX::CallbackHandler->new
  (@args,
   cb_key       => 'set_arg_one',
   trigger_key  => 'ToTest|set_arg_one_cb4',
  );

$to_test->set_arg_one;
is $to_test->request_args->{one}, 'success', 'Check for success';

$to_test = MasonCallbacksToTest->new(@args);
$to_test->redir;
ok $to_test->redirected, "Check that it redirected";

$to_test = MasonCallbacksToTest->new(@args, value => '');
eval { $to_test->redir};
ok $to_test->aborted, "Check that redirect aborted";

