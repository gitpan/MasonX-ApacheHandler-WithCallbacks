package MasonX::CallbackHandle;

use strict;
use HTML::Mason::Exceptions ();
use Apache::Constants qw(REDIRECT);
use Class::Container ();
use HTML::Mason::MethodMaker( read_only => [qw(ah
                                               request_args
                                               apache_req
                                               priority
                                               cb_key
                                               pkg_key
                                               trigger_key
                                               value)] );

use vars qw($VERSION @ISA);
@ISA = qw(Class::Container);

$VERSION = '0.90';

Params::Validate::validation_options
  ( on_fail => sub { HTML::Mason::Exception::Params->throw( join '', @_ ) } );

__PACKAGE__->valid_params
  ( ah           =>
    { isa        => 'MasonX::ApacheHandler::WithCallbacks',
      descr      => 'ApacheHandler::WithCallbacks object'
    },

    request_args =>
    {  type      => Params::Validate::HASHREF,
       desc      => 'Request arguments'
    },

    apache_req   =>
    { isa        => 'Apache',
      desc       => 'Apache request object'
    },

    priority =>
    { type      => Params::Validate::SCALAR,
      callbacks => { 'valid priority' => sub { $_[0] =~ /^\d$/ } },
      optional  => 1,
      desc      => 'Priority'
    },

    cb_key =>
    { type      => Params::Validate::SCALAR,
      optional  => 1,
      desc      => 'Callback key'
    },

    pkg_key =>
    { type      => Params::Validate::SCALAR,
      optional  => 1,
      desc      => 'Package key'
    },

    trigger_key =>
    { type      => Params::Validate::SCALAR,
      optional  => 1,
      desc      => 'Trigger key'
    },

    value =>
    { type      => Params::Validate::SCALAR | Params::Validate::ARRAYREF,
      optional  => 1,
      desc      => 'Callback value'
    },

  );

sub redirect {
    my ($self, $url, $wait, $status) = @_;
    $status ||= REDIRECT;
    my $r = $self->apache_req;
    $r->method('GET');
    $r->headers_in->unset('Content-length');
    $r->err_header_out( Location => $url );
    my $ah = $self->ah;
    # Should I use accessors here?
    $ah->{_status} = $status;
    $ah->{redirected} = $url;
    $self->abort($status) unless $wait;
}

sub redirected { $_[0]->ah->redirected }

sub abort {
    my ($self, $aborted_value) = @_;
    # Should I use an accessor here?
    $self->ah->{_status} = $aborted_value;
    HTML::Mason::Exception::Abort->throw
        ( error => __PACKAGE__ . '->abort was called',
          aborted_value => $aborted_value );
}

sub aborted {
    my ($self, $err) = @_;
    $err = $@ unless defined $err;
    return HTML::Mason::Exceptions::isa_mason_exception( $err, 'Abort' );
}

1;
__END__

=head1 NAME

MasonX::CallbackHandle - Callback Requst Data and Utility Methods

=head1 SYNOPSIS

  sub my_callback {
      my $cbh = shift;
      my $args = $cbh->request_args;
      my $value = $cbh->value;
      # Do stuff with above data.
      $cbh->redirect($url);
  }

=head1 DESCRIPTION

MasonX::CallbackHandle objects are constructed by
MasonX::ApacheHandler::WithCallbacks and passed in as the sole argument for
every execution of a callback code reference. See
L<MasonX::ApacheHandler::WithCallbacks|MasonX::ApacheHandler::WithCallbacks>
for details on how to configure it to execute your callback code.

=head1 INTERFACE

MasonX::CallbackHandle objects are created by
MasonX::ApacheHandler::WithCallbacks, and should never be constructed
directly. However, you'll find them very useful when they're passed to your
callback code references. Here's a listing of the goodies you'll find.

=head2 Accessor Methods

All of the MasonX::CallbackHandle accessor methods are read-only.

=over 4

=item C<ah>

  my $ah = $cbh->ah;

Returns a reference to the MasonX::ApacheHandler::WithCallbacks object that
executed the callback.

=item C<request_args>

  my $args = $cbh->request_args;

Returns a reference to the Mason request arguments hash. This is the hash that
will be used to create the C<%ARGS> hash and the C<< <%args> >> block
variables in your Mason components. Any changes you make to this hash will
percolate back to your components.

=item C<apache_req>

  my $r = $cbh->apache_req;

Returns the Apache request object for the current request. If you've told
Mason to use Apache::Request, it is the Apache::Request object that will be
returned. Otherwise, if you're having CGI process your request arguments, then
it will be the plain old Apache object.

=item C<priority>

  my $priority = $cbh->priority;

Returns the priority level at which the callback was executed. Possible values
are between "0" and "9".

=item C<cb_key>

  my $cb_key = $cbh->cb_key;

Returns the callback key that triggered the execution of the callback. For
example, this callback-triggering form field:

  <input type="submit" value="Save" name="DEFAULT|save_cb" />

Will cause the C<cb_key()> method in the relevant callback to return "save".

=item C<pkg_key>

  my $pkg_key = $cbh->pkg_key;

Returns the package key used in the callback trigger field. For example, this
callback-triggering form field:

  <input type="submit" value="Save" name="MyCBs|save_cb" />

Will cause the C<pkg_key()> method in the relevant callback to return "MyCBs".

=item C<value>

  my $value = $cbh->value;

Returns the value of the callback trigger field. If there is more than one
value for the callback trigger field, then C<value()> will return an array
reference. For examle, for this callback field:

  <input type="hidden" value="foo" name="DEFAULT|save_cb" />

the value returned by C<value()> will be "foo". For this example, however:

  <input type="hidden" value="foo" name="DEFAULT|save_cb" />
  <input type="hidden" value="bar" name="DEFAULT|save_cb" />

C<value()> will return the two-element array reference C<['foo', 'bar']>. If
you override the priority, however, or if the fields have different
priorities, then you can expect the callback to be called twice. For example,
these form fields:

  <input type="hidden" value="foo" name="DEFAULT|save_cb3" />
  <input type="hidden" value="bar" name="DEFAULT|save_cb2" />

will cause the relevant callback to be called twice. The first time,
C<value()> will return "bar", and the second time, it will return "foo".

Although you may often be able to retrieve the value directly from the hash
reference returned by C<request_args()>, if multiple callback keys point to
the same subroutine or if the form overrode the priority, you may not be able
to figure which value or values were submitted for a particular callback
execution. So MasonX::CallbackHandle nicely provides the value or values for
you.

=item C<trigger_key>

  my $trigger_key = $cbh->trigger_key;

Returns the request argument key that triggered the callback. This is the
complete name used in the HTML field that triggered the callback. For example,
if the field that triggered the callback looks like this:

  <input type="submit" value="Save" name="MyCBs|save_cb6" />

then the value returned by C<trigger_key()> method will be "MyCBs|save_cb6".

B<Note:> Most browers will submit "image" input fields with two arguments, one
with ".x" appended to its name, and the other with ".y" appended to its
name. MasonX:::ApacheHandler::WithCallbacks will ignore these fields and
either use the field named without the ".x" or ".y", or create a field with
that name and give it a value of "1". The reasoning behind this approach is
that the names of the callback-triggering fields should be the same as the
names that appear in the form fields.

=item C<redirected>

  $cbh->redirect($url) unless $cbh->redirected;

If the request has been redirected, this method returns the rediretion
URL. Otherwise, it eturns false. This method is useful for conditions in which
one callback has called C<< $cbh->redirect >> with the optional C<$wait>
argument set to a true value, thus allowing subsequent callbacks to continue
to execute. If any of those subsequent callbacks want to call
C<< $cbh->redirect >> themselves, they can check the value of
C<< $cbh->redirected >> to make sure it hasn't been done already.

=back

=head2 Other Methods

The MasonX::CallbackHandle object has a few other publicly accessible
methods.

=over 4

=item C<redirect>

  $cbh->redirect($url);
  $cbh->redirect($url, $status);
  $cbh->redirect($url, $status, $wait);

Given a URL, this method generates a proper HTTP redirect for that URL. By
default, the status code used is "302", but this can be overridden via the
C<$status> argument. If the optional C<$wait> argument is true, any callbacks
scheduled to be executed after the call to C<redirect> will continue to be
executed. In that clase, C<< $cbh->abort >> will not be called; rather,
MasonX::ApacheHandler::WithCallbacks will finish executing all remaining
callbacks and then check the status and abort before Mason creates and
executes a component stack. If the C<$wait> argument is unspecified or false,
then the request will be immediately terminated without executing subsequent
callbacks or, of course, any Mason components. This approach relies on the
execution of C<< $cbh->abort >>.

Since by default C<< $cbh->redirect >> calls C<< $cbh->abort >>, it will be
trapped by an C< eval {} > block. If you are using an C<eval {}> block in your
code to trap errors, you need to make sure to rethrow these exceptions, like
this:

  eval {
      ...
  };

  die $@ if $cbh->aborted;

  # handle other exceptions

=item C<abort>

  $cbh->abort($status);

Ends the current request without executing any more callbacks or any Mason
components. The C<$status> argument specifies the HTTP request status code to
be returned to Apache.

C<abort> is implemented by throwing an HTML::Mason::Exception::Abort object
and can thus be caught by C<eval()>. The C<aborted> method is a shortcut for
determining whether a caught error was generated by C<abort>.

=item C<aborted>

  die $err if $cbh->aborted;
  die $err if $cbh->aborted($err);

Returns true or C<undef> indicating whether the specified C<$err> was
generated by C<abort>. If no C<$err> argument is passed, C<aborted> examines
C<$@>, instead.

In this code, we catch and process fatal errors while letting C<abort>
exceptions pass through:

  eval { code_that_may_fail_or_abort() };
  if ($@) {
      die $@ if $cbh->aborted;

      # handle fatal errors...
  }

C<$@> can lose its value quickly, so if you're planning to call C<<
$cbh->aborted >> more than a few lines after the C<eval>, you should save
C<$@> to a temporary variable and pass it explicitly via the C<$err> argument.

=back

=head1 SEE ALSO

L<MasonX::ApacheHandler::WithCallback|MasonX::ApacheHandler::WithCallback>
constructs MasonX::CallbackHandle objects and passes them as the sole
argument to callback code references.

=head1 AUTHOR

David Wheeler <L<david@wheeler.net|"david@wheeler.net">>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
