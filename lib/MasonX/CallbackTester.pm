package MasonX::CallbackTester;
use strict;
use MasonX::CallbackHandler;
use Apache::FakeRequest;
use vars qw($VERSION);
$VERSION = '1.00';

# Make sure that Apache::FakeRequest is actuall an Apache class. Should be
# in mod_perl 1.28, anyway.
@Apache::FakeRequest::ISA = qw(Apache) unless @Apache::FakeRequest::ISA;

##############################################################################
# MasonX::CallbackHandler->redirect needs to call unset() on an object
# returned by $apache_req->headers_in().
package MasonX::CallbackTester::Headers;
sub unset {}
my $obj = bless {}, __PACKAGE__;

{
    local $^W;
    *Apache::FakeRequest::headers_in = sub { $obj };
}

##############################################################################
# Fake out the loading of MasonX::ApacheHandler::WithCallbacks.
package MasonX::ApacheHandler::WithCallbacks;
$MasonX::ApacheHandler::WithCallbacks::VERSION =
  $MasonX::CallbackTester::VERSION;
use File::Spec::Functions qw(catfile);
BEGIN {
    # Is this legal?
    $INC{catfile qw(MasonX ApacheHandler WithCallbacks.pm)} =
      $INC{catfile qw(MasonX CallbackTester.pm)};
}

# Might we need more here?
sub new { bless {} }
sub redirected { shift->{redirected} }

1;
__END__

=head1 NAME

MasonX::CallbackTester - Simplifies testing of MasonX::CallbackHandler subclasses

=head1 SYNOPSIS

  use strict;
  use Test::More tests => 1;
  use MasonX::CallbackTester;
  use My::CallbackPackage;
  use My::CallbackClass;

  my $ah = MasonX::ApacheHandler::WithCallbacks->new;
  my $apache_req = Apache::FakeRequest->new;

  # Test functional callbacks.
  my $cbh = MasonX::CallbackHandler->new( request_args => { one => 1 },
                                          apache_req   => $apache_req,
                                          ah           => $ah,
                                          priority     => 4,
                                          pkg_key      => 'myCBPkg',
                                          cb_key       => 'kill_it',
                                          trigger_key  => 'myCBPkg|kill_it_cb',
                                          value        => 1
                                        );

  eval { My::CallbackPackage::kill_it($cbh) };
  ok( $cbh->aborted($@), "Check that it aborted" );

  my $cbh = My::CallbackClass->new( request_args => { one => 1 },
                                    apache_req   => $apache_req,
                                    ah           => $ah,
                                    priority     => 4,
                                    pkg_key      => 'myCBClass',
                                    cb_key       => 'set_one',
                                    trigger_key  => 'myCBClass|set_one_cb',
                                    value        => 1
                                  );

  $cbh->set_one;
  is( $cbh->request_args->{one}, 1, "Check one for 1" );

=head1 DESCRIPTION

This package sets up a number of packages and convenience methods to simplify
the testing of callbacks to be used with
MasonX::ApacheHandler::WithCallbacks. Use it when writing tests to for your
functional callbacks or MasonX::CallbackHandler subclasses. Just be sure to
load it before you load any packages or classes that C<use
MasonX::ApacheHandler::WithCallbacks>, as it will set up a fake
MasonX::ApacheHandler::WithCallbacks package to prevent problems running
outside of a mod_perl environment.

The idea behind testing your callback methods and functions is to make sure
that they work as expected. Once you've executed a callback, you can use the
MasonX::CallbackHandler methods to examine your callback's handiwork. For
example, if the callback should set a particular request argument to a certain
value, you can check it. Or it it was supposed to redirect the request, you
can catch that redirect in an C<eval {}>.

Of course, to get started, you'll need to construct a MasonX::CallbackHandler
object (or MasonX::CallbackHandler subclass object) on which to run your
tests. In addition to whatever parameters you've specified for your
MasonX::CallbackHandler subclass, you'll need to know what arguments to pass
to keep MasonX::CallbackHandler's constructor happy. So here they are:

=over

=item C<apache_req>

Required. An Apache request object. Since we're of course not using Apache
outside of Apache, use Apache::FakeRequest, instead. MasonX::CallbackTester
nicely loads this class for you and makes it plays nice with
MasonX::CallbackHandler.

=item C<ah>

Required. A MasonX::ApacheHandler::WithCallbacks
object. MasonX::CallbackTester creates a fake
MasonX::ApacheHandler::WithCallbacks so that the real
MasonX::ApacheHandler::WithCallbacks doesn't try to load the mod_perl API.
Just be sure to C<use MasonX::CallbackTester> before you
C<use MasonX::ApacheHandler::WithCallbacks> or any packages that use it.

=item C<request_args>

Required. A hash reference of the key => value pairs you expect to be
submitted in a request. This is the same as what will eventually become the
C<%ARGS> hash in your Mason components and will be used for your
C<< <%args> >> block variables.

=item C<priority>

Optional. The priority with which the callback will be called.

=item C<pkg_key>

Optional. The package key or class key with which the callback will be
called. For MasonX::CallbackHandler subclasses, this will be the value of the
class key, of course. Sorry, there is no C<class_key> parameter.

=item C<cb_key>

Optional. The callback key with which the callback will be called. For
MasonX::CallbackHandler subclasses, this will be the same as the name of the
callback method itself.

=item C<trigger_key>

Optional. The full key that will trigger the callback. This parameter usually
should have the value "$pkg_key|$cb_key\_cb", although sometimes the priority
will be appended to it, as well.

=item C<value>

Optional. The value passed via the callback key in the request arguments. Note
that if you expect your callback to process a request with multiple values for
the same C<trigger_key>, they should all be included in an array reference.

=back

=head1 SEE ALSO

L<MasonX::CallbackHandler|MasonX::CallbackHandler> defines the interface for
callback classes. You'll want to be familiar with this class before you find a
use for MasonX::CallbackTester.

L<MasonX::ApacheHandler::WithCallbacks|MasonX::ApacheHandler::WithCallbacks>
constructs MasonX::CallbackHandler objects and executes the appropriate
callback functions and/or methods. It's worth a read.

L<Apache::FakeRequest|Apache::FakeRequest> allows you to create ad-hoc fake
Apache request objects. If your callbacks do a lot of stuff with the apache
request object, you may need to read up on Apache::FakeRequest to get it to do
what you need it to do.

=head1 AUTHOR

David Wheeler <david@wheeler.net>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
