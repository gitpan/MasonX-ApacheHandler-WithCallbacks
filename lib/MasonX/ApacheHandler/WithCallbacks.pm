package MasonX::ApacheHandler::WithCallbacks;

# $Id: WithCallbacks.pm,v 1.4 2003/01/03 06:43:25 david Exp $

use strict;
use HTML::Mason qw(1.10);
use HTML::Mason::ApacheHandler ();
use HTML::Mason::Exceptions ();
use Apache::Constants qw(REDIRECT);
use Params::Validate ();

use Exception::Class ( 'HTML::Mason::Exception::Callback::InvalidKey' =>
		       { isa => 'HTML::Mason::Exception',
			 description => 'No callback found for callback key',
			 fields => [ 'callback_key' ] },

                       'HTML::Mason::Exception::Callback::Execution' =>
		       { isa => 'HTML::Mason::Exception',
			 description => 'Error thrown by callback',
			 fields => [ 'callback_error' ] },
		     );

use HTML::Mason::MethodMaker( read_only => [qw(default_priority
                                               default_pkg_key
                                               redirected
                                               apache_req)] );

use vars qw($VERSION @ISA);
@ISA = qw(HTML::Mason::ApacheHandler);

$VERSION = '0.10';

Params::Validate::validation_options
  ( on_fail => sub { HTML::Mason::Exception::Params->throw( join '', @_ ) } );

__PACKAGE__->valid_params
  ( default_priority =>
    { type      => Params::Validate::SCALAR,
      parse     => 'string',
      callbacks => { 'valid priority' => sub { $_[0] =~ /^\d$/ } },
      default   => 5,
      descr     => 'Default callback priority'
    },

    default_pkg_key =>
    { type      => Params::Validate::SCALAR,
      parse     => 'string',
      default   => 'DEFAULT',
      callbacks => { 'valid package key' => sub { $_[0] } },
      descr     => 'Default package key'
    },

    callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      descr     => 'Callback specifications'
    },

    pre_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      descr     => 'Callbacks to be executed before argument callbacks'
    },

    post_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      descr     => 'Callbacks to be executed after argument callbacks'
    },

  );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    if (my $cb_specs = delete $self->{callbacks}) {
        my %cbs;
        foreach my $spec (@$cb_specs) {
            # Set the default package key.
            $spec->{pkg_key} ||= $self->{default_pkg_key};

            # Make sure that we have a callback key.
            HTML::Mason::Exceptions::Params->throw
              ( error => "Missing or invalid callback key" )
                unless $spec->{cb_key};

            # Make sure that we have a valid priority.
            if (defined $spec->{priority}) {
                HTML::Mason::Exceptions::Params->throw
                  ( error => "Not a valid priority: '$spec->{priority}'" )
                  unless $spec->{priority} =~ /^\d$/;
            } else {
                # Or use the default.
                $spec->{priority} = $self->{default_priority};
            }

            # Make sure that we have a code reference.
            HTML::Mason::Exceptions::Params->throw
              ( error => "Callback for package key '$spec->{pkg_key}' and " .
                         "callback key '$spec->{cb_key}' not a code reference"
              ) unless ref $spec->{cb} eq 'CODE';

            # Make sure that the key isn't already in use.
            HTML::Mason::Exceptions::Params->throw
              ( error => "Callback key '$spec->{cb_key}' already used by " .
                "package key '$spec->{pkg_key}'"
              ) if $cbs{$spec->{pkg_key}}->{$spec->{cb_key}};

            # Set it up.
            $cbs{$spec->{pkg_key}}->{$spec->{cb_key}} =
              { cb => $spec->{cb}, priority => $spec->{priority} };
        }
        $self->{_cbs} = \%cbs;
    }

    # Now validate and store any global callbacks.
    foreach my $type (qw(pre post)) {
        if (my $cbs = delete $self->{$type . '_callbacks'}) {
            my @gcbs;
            foreach my $cb (@$cbs) {
                # Make sure that we have a code reference.
                HTML::Mason::Exceptions::Params->throw
                  ( error => "Global $type callback not a code reference" )
                  unless ref $cb eq 'CODE';
                push @gcbs, [$cb];
            }
            # Keep 'em.
            $self->{"_$type"} = \@gcbs;
        }
    }

    # Let 'em have it.
    return $self;
}

sub request_args {
    my $self = shift;
    my ($args, $r, $q) = $self->SUPER::request_args(@_);
    $self->{apache_req} = $r;

    my @cbs;
    if ($self->{_cbs}) {
        while (my ($k, $v) = each %$args) {
            # Strip off the '.x' that an <input type="image" /> tag creates.
            (my $chk = $k) =~ s/\.x$//;
            if ((my $key = $chk) =~ s/_cb(\d?)$//) {
                # It's a callback field. Grab the priority.
                my $priority = $1;

                if ($chk ne $k) {
                    # Some browsers will submit $k.x and $k.y instead of just
                    # $k for <input type="image" />, a field that can only be
                    # submitted once for a given page. So skip it if we've
                    # already seen this arg.
                    next if exists $args->{$chk};
                    # Otherwise, add the unadorned key to $args with a true
                    # value.
                    $args->{$chk} = 1;
                }

                # Find the package key and the callback key.
                my ($pkg_key, $cb_key) = split /\|/, $key, 2;
                next unless $pkg_key;

                # Find the callback.
                my $cb = $self->{_cbs}{$pkg_key}{$cb_key}{cb} or
                  HTML::Mason::Exception::Callback::InvalidKey->throw
                    ( error   => "No callback found for callback key '$chk'",
                      callback_key => $chk );

                # Get the specified priority if none was included in the
                # callback key.
                $priority = $self->{_cbs}{$pkg_key}{$cb_key}{priority}
                  unless $priority ne '';

                # Push the callback onto the stack, along with the value and
                # the callback key (since different keys can point to the same
                # code reference).
                push @{$cbs[$priority]}, [$cb, $v, $cb_key];
            }
        }
    }

    # Put any pre and post callbacks onto the stack.
    unshift @cbs, $self->{_pre} if $self->{_pre};
    push @cbs, $self->{_post} if $self->{_post};

    # Now execute the callbacks.
    eval {
      RUNCBS: foreach my $cb_list (@cbs) {
            # Skip it if there are no callbacks for this priority.
            next unless $cb_list;
            foreach my $cb_data (@$cb_list) {
                # Grab the callback and execute it.
                my ($cb, @data) = @$cb_data;
                $cb->($self, $args, @data);
            }
        }
    };

    # Handle any error.
    if (my $err = $@) {
        my $ref = ref $err;
        unless ($ref) {
            # Raw error -- create an exception to throw.
            HTML::Mason::Exception::Callback::Execution->throw
                ( error => "Error thrown by callback: $err",
                  callback_error => $err );
        } elsif ($self->aborted($err)) {
            # They aborted. Do nothing, since Mason will check the
            # request status and do the right thing.
        } else {
            # Just die.
            die $err;
        }
    }

    # We now return to normal Mason processing.
    return ($args, $r, $q);
}

sub redirect {
    my ($self, $url, $wait, $status) = @_;
    $status ||= REDIRECT;
    my $r = $self->apache_req;
    $r->method('GET');
    $r->headers_in->unset('Content-length');
    $r->err_header_out( Location => $url );
    $r->status($status);
    $self->{redirected} = $url;
    $self->abort($status) unless $wait;
}

sub abort {
    my ($self, $aborted_value) = @_;
    $self->{aborted} = 1;
    HTML::Mason::Exception::Abort->throw
        ( error => __PACKAGE__ . '->abort was called',
          aborted_value => $aborted_value );
}

sub aborted {
    my ($self, $err) = @_;
    $err = $@ unless defined($err);
    return HTML::Mason::Exceptions::isa_mason_exception( $err, 'Abort' );
}

1;

__END__

=head1 NAME

MasonX::ApacheHandler::WithCallbacks - Execute code before Mason components

=head1 SYNOPSIS

=begin comment

In F<httpd.conf>:

  PerlModule My::Callbacker
  # Must load last:
  PerlModule MasonX::ApacheHandler::WithCallbacks
  <Location /mason>
    SetHandler perl-script
    PerlHandler MasonX::ApacheHandler::WithCallbacks
  </Location>

=end comment

In F<handler.pl>:

  use strict;
  use MasonX::ApacheHandler::WithCallbacks;

  sub calc_time {
      my ($cbh, $args, $val, $key) = @_;
      $args->{answer} = localtime($val || time);
  }

  my $ah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { cb_key => calc_time,
                       cb => \&calc_time } ]
    );

  sub handler {
      my $r = shift;
      $ah->handle_request($r);
  }

In your component:

  % if (exists $ARGS{answer}) {
        <p><b>Answer: <% $ARGS{answer} %></b></p>
  % } else {
  <form>
  <p>Enter an epoch time: <input type="text" name="epoch_time" /><br />
  <input type="submit" name="myCallbacker|calc_time_cb" value="Calculate" />
  </p>
  </form>
  % }

=begin comment

=head1 ABSTRACT

MasonX::ApacheHandler::WithCallbacks subclasses HTML::Mason::ApacheHandler in
order to provide callbacks. Callbacks are executed at the beginning of a
request, just before Mason creates a component stack and executes the
components.

=end comment

=head1 DESCRIPTION

MasonX::ApacheHandler::WithCallbacks subclasses HTML::Mason::ApacheHandler in
order to provide callbacks. Callbacks are code references provided to the
C<new()> constructor, and are triggered either for every request or by
specially named keys in the Mason request arguments. The callbacks are
executed at the beginning of a request, just before Mason creates a component
stack and executes the components.

The idea is to configure Mason to execute arbitrary code before executing any
components. Doing so allows you to carry out logical processing of data
submitted from a form, to affect the contents of the Mason request arguments
(and thus the C<%ARGS> hash in components), and even to redirect or abort the
request before Mason handles it.

=head1 JUSTIFICATION

Why would you want to do this? Well, there are a number of reasons. Some I can
think of offhand include:

=over 4

=item Stricter separation of logic from presentation

Most application logic handled in Mason components takes place in
C<< <%init> >> blocks, often in the same component as presentation logic. By
moving the application logic into subroutines in Perl modules and then
directing Mason to execute those subroutines as callbacks, you obviously
benefit from a cleaner separation of application logic and presentation.

=item Wigitization

Thanks to their ability to preprocess arguments, callbacks enable developers
to develop easier-to-use, more dynamic widgets that can then be used in any
Mason components. For example, a widget that puts many related fields into a
form (such as a date selection widget) can have its fields preprocessed by a
callback (for example, to properly combine the fields into a unified date
field) before the Mason component that responds to the form submission gets
the data.

=item Shared Memory

Callbacks are just Perl subroutines in modules loaded at server startup
time. Thus the memory they consume is all in the parent, and then shared by
the Apache children. For code that executes frequently, this can be much less
resource-intensive than code in Mason components, since components are loaded
separately in each Apache child process (unless they're preloaded via the
C<preloads> parameter to the HTML::Mason::Interp constructor).

=item Performance

Since callbacks are executed before Mason creates a component stack and
executes the components, they have the opportunity to short-circuit the Mason
processing by doing something else. A good example is redirection. Often the
application logic in callbacks does its thing and then redirects the user to a
different page. Executing the redirection in a callback eliminates a lot of
extraneous processing that would otherwise be executed before the redirection,
creating a snappier response for the user.

=back

And if those are enough reasons, then just consider this: Callbacks just I<way
cool.>

=head1 USAGE

MasonX::ApacheHandler::WithCallbacks supports two different types of
callbacks: those triggered by a specially named key in the Mason request
arguments hash, and those executed for every request.

=head2 Argument-Triggered Callbacks

Argument-triggered callbacks are triggered by specially named request
arguments keys. These keys are constructed as follows: The package name
followed by a pipe character ("|"), the callback key with the string "_cb"
appended to it, and finally an optional priority number at the end. For
example, if you specified a callback with the callback key "save" and the
package key "world", a callback field might be added to an HTML form like
this:

  <input type="button" value="Save World" name="world|save_cb" />

This field, when submitted to the Mason server, would trigger the callback
associated with the "save" callback key in the "world" package. If such a
callback hasn't been configured, then MasonX::ApacheHandler::WithCallbacks
will throw a HTML::Mason::Exception::Callback::InvalidKey exception. Here's
how to configure such a callback when constructing your
MasonX::ApacheHandler::WithCallbacks object so that that doesn't hapen:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { pkg_key => 'world',
                       cb_key  => 'save',
                       cb      => \&My::World::save } ] );

With this configuration, the request argument created by the above HTML form
field will trigger the exectution of the C<&My::World::save> subroutine.

=head3 Callback Subroutines

The code references used for argument-triggered callbacks should accept four
arguments, generally looking something like this:

  sub foo {
      my ($cbh, $args, $val, $key) = @_;
      # Do stuff.
  }

The arguments are as follows:

=over 4

=item <$cbh>

The first argument is the MasonX::ApacheHandler::WithCallbacks object
itself. Use its C<redirect()> method to redirect the request to a new URL or
the C<apache_req()> accessor to retrieve the Apache request object.

=item C<$args>

A reference to the Mason request arguments hash. This is the hash that will be
used to create the C<%ARGS> hash and the C<< <%args> >> block variables in
your Mason components. Any changes you make to this hash will percolate back
to your components.

=item C<$val>

The value of the callback trigger field. Although you may often be able to
retrieve this value directly from the C<$args> hash reference, if multiple
callback keys point to the same subroutine or if the form overrode the
priority, you may not be able to figure it out. So
MasonX::ApacheHandler::WithCallbacks nicely passes in the value for you.

=item C<$cb_key>

The callback key that triggered the execution of the subroutine. In the
example configuration above provided that the C<My::World::save()> subroutine
was triggered by a request argument, then the value of the C<$cb_key> argument
would be "save".

=back

Note that all callbacks are executed in a C<eval {}> block, so if any of your
callback subroutines C<die>, MasonX::ApacheHandler::WithCallbacks will
throw an HTML::Mason::Exception::Callback::Execution exception.

=head3 The Package Key

The use of the package key is a convenience so that a system with many
callbacks can use callbacks with the same keys but in different packages. The
idea is that the package key will uniquely identify the module in which each
callback subroutine is found, but it doesn't necessarily have to be so. Use
the package key any way you wish, or not at all:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { cb_key  => 'save',
                       cb      => \&My::World::save } ] );

But note that if you don't use the package key at all, you'll still need to
provide one in the field to be submitted to the Mason server. By default, that
key is "DEFAULT". Such a callback field in an HTML form would then look like
this:

  <input type="button" value="Save World" name="DEFAULT|save_cb" />

If you don't like the "DEFAULT" package name, you can set an alternative
default using the C<default_pkg_name> parameter to C<new()>:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key  => 'save',
                              cb      => \&My::World::save } ],
      default_pkg_name => 'MyPkg' );

Then, of course, any callbacks without a specified package key of their own
will then use the custom default:

  <input type="button" value="Save World" name="MyPkg|save_cb" />

=head3 Priority

Sometimes one callback is more important than anoether. For example, you might
rely on the execution of one callback to set up variables needed by as a
priority level seven callback another callback. Since you can't rely on the
order in which callbacks are executed (the Mason request arguments are stored
in a hash, and the processing of a hash is, of course, unordered), you need
a method of ensuring that the setup callback executed first.

In such a case, you can set a higher priority level for the setup callback
than for other callbacks:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key   => 'setup',
                              priority => 3,
                              cb       => \&setup },
                            { cb_key   => 'save',
                              cb       => \&save }
                          ] );

In this example, the "setup" callback has been configured with a priority
level of "3". This ensures that it will always execute before the "save"
callback, which has the default priority of "5". This is true regardless
of the order of the fields in the corresponding HTML::Form:

  <input type="button" value="Save World" name="DEFAULT|save_cb" />
  <input type="hidden" name="DEFAULT|setup_cb" value="1" />

Despite the fact that the "setup" callback field appears after the "save"
field (and will generally be submitted by the browser in that order), the
"setup" callback will always execute first because of its higher priority.

Although the "save" callback got the default priority of "5", this too can be
customized to a different priority level via the C<default_priority> parameter
to C<new()>. For example, this configuration:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key   => 'setup',
                              priority => 3,
                              cb       => \&setup },
                            { cb_key   => 'save',
                              cb       => \&save }
                          ],
      default_priority => 2 );

Will cause the "save" callback to always execute before the "setup" callback,
since it's priority level will default to "2".

Conversely, the priority level can be overridden via the form submission field
itself by appending a priority level to the end of the callback field
name. Hence, this example:

  <input type="button" value="Save World" name="DEFAULT|save_cb2" />
  <input type="hidden" name="DEFAULT|setup_cb" value="1" />

causes the "save" callback to execute before the "setup" callback by
overriding the "save" callback's priority to level "2". Of course, any other
form field that triggers the "save" callback without a priority override will
still execute "save" at its configured level.

=head2 Request Callbacks

Request callbacks come in two separate flavors: those that execute before the
argument-triggered callbacks, and those that execute after the
argument-triggered callbacks. These may be specified via the C<pre_callbacks>
and C<post_callbacks> parameters to C<new()>, respectively:

  my $cbh = MasonX::ApacheHandler::WithCallbacks->new
    ( pre_callbacks  => [ \&translate, \&foobarate ],
      post_callbacks => [ \&escape, \&negate ] );

In this example, the C<translate()> and C<foobarate()> subroutines will
execute (in that order) before any argument-triggered callbacks are executed
(none will be in this example, since none are specifed). Conversely, the
C<escape()> and C<negate()> subroutines will be executed (in that order) after
all argument-triggered callbacks have been executed. And regardless of what
argument-triggered callbacks may be triggered, the request callbacks will
always be executed for I<every> request.

Although they may be used for different purposes, the C<pre_callbacks> and
C<post_callbacks> callback code references expect the same arguments:

  sub foo {
      my ($cbh, $args) = @_;
  }

Like the argument-triggered callbacks, the request callbacks get the
MasonX::ApacheHandler::WithCallbacks object and the Mason request arguments
hash. But since they're executed for every request (and there likely won't be
many of them), they have no other arguments.

Also like the argument-triggered callbacks, request callbacks are executed in
a C<eval {}> block, so if any of them C<die>s, an
HTML::Mason::Exception::Callback::Execution exception will be thrown.

=head1 INTERFACE

=head2 Parameters To The C<new()> Constructor

In addition to those offered by the HTML::Mason::ApacheHandler base class,
this module supports a number of parameters to the C<new()> constructor.

=over 4

=item C<callbacks>

Argument-triggered callbacks are configured via the C<callbacks> parameter.
This parameter is an array reference of hash references, and each hash
reference specifies a single callback. The supported keys in the callback
specification hashes are:

=over 4

=item C<cb_key>

Required. A string that, when found in a properly-formatted Mason request
argument key, will trigger the execution of the callback.

=item C<cb>

Required. A reference to the Perl subroutine that will be executed when the
C<cb_key> has been found in a Mason request argument key. Each code reference
should expect four arguments, the ApacheHandler::WithCallbacks object, the
Mason request arguments hash reference, the value of the argument hash key
that triggered the callback, and the callback key pointing to this code
reference. Since this last argument will most often be equivalent to
C<cb_key>, you can safely ignore it except in those cases where you might have
more than one callback pointing to the same code reference.

=item C<pkg_key>

Optional. A key to uniquely identify the package in which the callback
subroutine is found. This parameter is useful in systems with many callbacks,
where developers may wish to use the same C<cb_key> for different subroutines
in different packages. The default package key may be set via the
C<default_pkg_key> parameter.

=item C<priority>

Optional. Indicates the level of priority of a callback. Some callbacks are
more important than others, and should be executed before others.
MasonX::ApacheHandler::WithCallbacks supports priority levels, ranging from
"0" (highest priority) to "9" (lowest priority). The default priority may be
set via the C<default_priority> parameter.

=back

=item C<pre_callbacks>

This parameter accepts an array reference of code references that should be
executed for I<every> request, I<before> any other callbacks. Each code
reference should expect two arguments: the ApacheHandler::WithCallbacks object
and a reference to the Mason request arguments hash. Use this feature when you
want to do something with the arguments sumitted for every request, such as
convert character sets.

=item C<post_callbacks>

This parameter accepts an array reference of code references that should be
executed for I<every> request, I<after> all other callbacks have been
called. Each code reference should expect two arguments: the
ApacheHandler::WithCallbacks object and a reference to the Mason request
arguments hash. Use this feature when you want to do something with the
arguments sumitted for every request, such as HTML-escape their values.

=item C<default_priority>

The priority level at which callbacks will be executed. This is the value that
will be used for the C<priority> key in each hash reference passed via the
C<callbacks> parameter to C<new()>. You may specify a default priority level
within the range of "0" (highst priority) to "9" (lowest priority). If not
specified, it defaults to "5".

=item C<default_pkg_key>

The default package key for callbacks. This is the value that will be used for
the C<pkg_key> key in each hash referenced passed via the C<callbacks>
parameter to C<new()>. It can be any string that evaluates to a true value,
and defaults to "DEFAULT" if not specified.

=back

=head2 ACCESSOR METHODS

The properties C<default_priority> and C<default_pkg_key> have standard
read-only accessor methods of the same name. For example:

  my $cbh = new HTML::Mason::ApacheHandler::WithCallbacks;
  my $default_priority = $cbh->default_priority;
  my $default_pkg_key = $cbh->default_pkg_key;

=head2 OTHER METHODS

The ApacheHandler::WithCallbacks object has a few other publicly accessible
methods.

=over 4

=item C<apache_req>

  my $r = $cbh->apache_req;

Returns the Apache request object for the current request. If you've told
Mason to use Apache::Request, it is the Apache::Request object that will be
returned. Otherwise, if you're having CGI process your request arguments, then
it will be the plain old Apache object.

=item C<redirect>

  $cbh->redirect($url);
  $cbh->redirect($url, $status);
  $cbh->redirect($url, $status, $wait);

Given a URL, this method generates a proper HTTP redirect for that URL. By
default, the status code used is "302", but this can be overridden via the
C<$status> argument. If the optional C<$wait> argument is true, any callbacks
scheduled to be executed after the call to C<redirect> will continue to be
executed. In that clase, C< $cbh->abort >> will not be called; rather, Mason
will wait for the callbacks to finish running and then check the status and
abort itself before creating a component stack or executing any components. If
the C<$wait> argument is unspecified or false, then the request will be
immediately terminated without executing subsequent callbacks. This approach
relies on the execution of C<< $cbh->abort >>.

Since by default C<< $cbh->redirect >> calls C<< $cbh->abort >>, it will be
trapped by an C< eval {} > block. If you are using an C< eval {} > block in
your code to trap errors, you need to make sure to rethrow these exceptions,
like this:

  eval {
      ...
  };

  die $@ if $cbh->aborted;

  # handle other exceptions

=item C<redirected>

  $cbh->redirect($url) unless $cbh->redirected;

If the request has been redirected, this method returns the rediretion
URL. Otherwise, it eturns false. This method is useful for conditions in which
one callback has called C<< $cbh->redirect >> with the optional C<$wait>
argument set to a true value, thus allowing subsequent callbacks to continue
to execute. If any of those subsequent callbacks want to call
C<< $cbh->redirect >> themselves, they can check the value of
C<< $cbh->redirected >> to make sure it hasn't been done already.

=item C<abort>

  $cbh->abort($status);

Ends the current request without executing any more callbacks or any Mason
components. The optional argument specifies the HTTP request status code to
be returned to Apache.

C<abort> is implemented by throwing an HTML::Mason::Exception::Abort object
and can thus be caught by C<eval()>. The C<aborted> method is a shortcut for
determining whether a caught error was generated by C<abort>.

=item C<aborted>

  die $err if $cbh->aborted($err);

Returns true or C<undef> indicating whether the specified C<$err> was
generated by C<abort>. If no C<$err> was passed, C<aborted> examines C<$@>,
instead.

In this code, we catch and process fatal errors while letting C<abort>
exceptions pass through:

  eval { code_that_may_fail_or_abort() };
  if ($@) {
      die $@ if $m->aborted;

      # handle fatal errors...
  }

C<$@> can lose its value quickly, so if you are planning to call
C<< $m->aborted >> more than a few lines after the eval, you should save
C<$@> to a temporary variable.

=back

=head1 SEE ALSO

This module works with L<HTML::Mason|HTML::Mason> by subclassing
L<HTML::Mason::ApacheHandler|HTML::Mason::ApacheHandler>. It is based on the
implementation of callbacks in Bricolage (L<http://bricolage.cc/>), though is
a completely new code base with a different approach.

=head1 ACKNOWLEDGEMENTS

Garth Webb implemented the original callbacks in Bricolage, based on an idea
he borrowed from Paul Lindner's work with Apache::ASP. My thanks to them both
for planting this great idea!

=head1 BUGS

Please report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MasonX-ApacheHandler-WithCallbacks>.

=head1 TODO

=over 4

=item *

Add some good real-world examples to the documentation.

=item *

Maybe add a CallbackRequest object to pass into the callbacks as the sole
argument instead of a bunch of invididual arguments?

=item *

Figure out how to use F<httpd.conf> C<PerlSetVar> directives to pass callback
specs to C<new()>.

=item *

Add tests for multiple packages supplying callbacks.

=item *

Add tests for error conditions.

=item *

Add tests for invalid parameters.

=back

=head1 AUTHOR

David Wheeler <L<david@wheeler.net|"david@wheeler.net">>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
