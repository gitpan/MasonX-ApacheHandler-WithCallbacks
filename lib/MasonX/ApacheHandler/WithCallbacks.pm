package MasonX::ApacheHandler::WithCallbacks;

# $Id: WithCallbacks.pm,v 1.26 2003/02/14 22:49:07 david Exp $

use strict;
use HTML::Mason qw(1.10);
use HTML::Mason::ApacheHandler ();
use HTML::Mason::Exceptions ();
use MasonX::CallbackHandle;
use Apache::Constants qw(HTTP_OK);
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
                                               redirected)] );

use vars qw($VERSION @ISA);
@ISA = qw(HTML::Mason::ApacheHandler);

$VERSION = '0.91';

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
      optional  => 1,
      descr     => 'Callback specifications'
    },

    pre_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      optional  => 1,
      descr     => 'Callbacks to be executed before argument callbacks'
    },

    post_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      optional  => 1,
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
            HTML::Mason::Exception::Params->throw
              ( error => "Missing or invalid callback key" )
                unless $spec->{cb_key};

            # Make sure that we have a valid priority.
            if (defined $spec->{priority}) {
                HTML::Mason::Exception::Params->throw
                  ( error => "Not a valid priority: '$spec->{priority}'" )
                  unless $spec->{priority} =~ /^\d$/;
            } else {
                # Or use the default.
                $spec->{priority} = $self->{default_priority};
            }

            # Make sure that we have a code reference.
            HTML::Mason::Exception::Params->throw
              ( error => "Callback for package key '$spec->{pkg_key}' and " .
                         "callback key '$spec->{cb_key}' not a code reference"
              ) unless ref $spec->{cb} eq 'CODE';

            # Make sure that the key isn't already in use.
            HTML::Mason::Exception::Params->throw
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
                HTML::Mason::Exception::Params->throw
                  ( error => "Global $type callback not a code reference" )
                  unless ref $cb eq 'CODE';
                push @gcbs, [$cb];
            }
            # Keep 'em.
            $self->{"_$type"} = \@gcbs;
        }
    }

    # Warn 'em if they're not using any callbacks.
    unless ($self->{_cbs} or $self->{_pre} or $self->{_post}) {
        warn "You didn't specify any callbacks. If you're not going" .
          "to use callbacks,\nyou might as well just use " .
          "HTML::Mason::ApacheHandler.\n";
    }

    # Let 'em have it.
    return $self;
}

sub request_args {
    my $self = shift;
    my ($args, $r, $q) = $self->SUPER::request_args(@_);

    # Use an array to store the callbacks according to their priorities. Why
    # an array when most of its indices will be undefined? Well, because I
    # benchmarked it vs. a hash, and found a very negligible difference when
    # the array had only element five filled (with no 6-9 elements) and the
    # hash had only one element. Furthermore, in all cases where the array had
    # two elements (with the other 8 undef), it outperformed the two-element
    # hash every time. But really this just starts to come down to very fine
    # differences compared to the work that the callbacks will likely be
    # doing, anyway. And in the meantime, the array is just easier to use,
    # since the priorities are just numbers, and its easist to unshift and
    # push on the pre- and post- request callbacks than to stick them onto a
    # hash. In short, the use of arrays is cleaner, easier to read and
    # maintain, and almost always just as fast or faster than using hashes. So
    # that's the way it'll be.
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

                # Push the callback onto the stack, along with the parameters
                # for the construction of the  MasonX::CallbackHandle object
                # that will be passed to it.
                push @{$cbs[$priority]}, [$cb, [ request_args => $args,
                                                 apache_req   => $r,
                                                 ah           => $self,
                                                 priority     => $priority,
                                                 cb_key       => $cb_key,
                                                 pkg_key      => $pkg_key,
                                                 trigger_key  => $chk,
                                                 value        => $v
                                               ]
                                         ];
            }
        }
    }

    # Put any pre and post callbacks onto the stack.
    unshift @cbs, $self->{_pre} if $self->{_pre};
    push @cbs, $self->{_post} if $self->{_post};

    # Now execute the callbacks.
    eval {
        foreach my $cb_list (@cbs) {
            # Skip it if there are no callbacks for this priority.
            next unless $cb_list;
            foreach my $cb_data (@$cb_list) {
                my ($cb, $cbh_params) = @$cb_data;
                # Construct the callback handle object.
                my $cbh = MasonX::CallbackHandle->new
                  ($cbh_params ? @$cbh_params :
                   ( request_args => $args,
                     apache_req   => $r,
                     ah           => $self ));
                # Execute the callback.
                $cb->($cbh);
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
        } elsif (HTML::Mason::Exceptions::isa_mason_exception($err, 'Abort')) {
            # They aborted. Do nothing, prepare_request() will check the
            # request status and do the right thing.
        } else {
            # Just pass exception objects on up the chain.
            die $err;
        }
    }

    # We now return to normal Mason processing.
    return ($args, $r, $q);
}

sub prepare_request {
    my $self = shift;
    my $m = $self->SUPER::prepare_request(@_);
    # Check our own status and return it, if necessary.
    if (ref $m and my $status = delete $self->{_status}) {
        return $status if $status != HTTP_OK;
    }
    # Everything is normal.
    return $m;
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
      my $cbh = shift;
      my $args = $cbh->request_args;
      my $val = $cbh->value;
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
order to provide callbacks. Callbacks are code references executed at the
beginning of a request, just before Mason creates and executes the request
component stack.

=end comment

=head1 DESCRIPTION

MasonX::ApacheHandler::WithCallbacks subclasses HTML::Mason::ApacheHandler in
order to provide callbacks. Callbacks are code references provided to the
C<new()> constructor, and are triggered either for every request or by
specially named keys in the Mason request arguments. The callbacks are
executed at the beginning of a request, just before Mason creates and executes
the request component stack.

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

Callbacks are just Perl subroutines in modules loaded at server startup time.
Thus the memory they consume is all in the parent, and then shared by the
Apache children. For code that executes frequently, this can be much less
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

=item Testing

Mason components are not easy to test via a testing framework such as
Test::Harness. Subroutines in modules, on the other hand, are fully
testable. This means that you can write tests in your application test suite
to test your callback subroutines.

=back

And if those are enough reasons, then just consider this: Callbacks just I<way
cool.>

=head1 USAGE

MasonX::ApacheHandler::WithCallbacks supports two different types of
callbacks: those triggered by a specially named key in the Mason request
arguments hash, and those executed for every request.

=head2 Argument-Triggered Callbacks

Argument-triggered callbacks are triggered by specially named request argument
keys. These keys are constructed as follows: The package name followed by a
pipe character ("|"), the callback key with the string "_cb" appended to it,
and finally an optional priority number at the end. For example, if you
specified a callback with the callback key "save" and the package key "world",
a callback field might be added to an HTML form like this:

  <input type="button" value="Save World" name="world|save_cb" />

This field, when submitted to the Mason server, would trigger the callback
associated with the "save" callback key in the "world" package. If such a
callback hasn't been configured, then MasonX::ApacheHandler::WithCallbacks
will throw a HTML::Mason::Exception::Callback::InvalidKey exception. Here's
how to configure such a callback when constructing your
MasonX::ApacheHandler::WithCallbacks object so that that doesn't hapen:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { pkg_key => 'world',
                       cb_key  => 'save',
                       cb      => \&My::World::save } ] );

With this configuration, the request argument created by the above HTML form
field will trigger the exectution of the C<&My::World::save> subroutine.

=head3 Callback Subroutines

The code references used for argument-triggered callbacks will be executed
with a single argument, a MasonX::CallbackHandle object. Thus, a callback
subroutine will generally look something like this:

  sub foo {
      my $cbh = shift;
      # Do stuff.
  }

The MasonX::CallbackHandle object provides accessors to data relevant to the
callback, including the callback key, the package key, and the request
arguments. It also includes C<redirect()> and C<abort()> methods. See the
L<MasonX::CallbackHandle|MasonX::CallbackHandle> documentation for all the
goodies.

Note that all callbacks are executed in a C<eval {}> block, so if any of your
callback subroutines C<die>, MasonX::ApacheHandler::WithCallbacks will
throw an HTML::Mason::Exception::Callback::Execution exception.

=head3 The Package Key

The use of the package key is a convenience so that a system with many
callbacks can use callbacks with the same keys but in different packages. The
idea is that the package key will uniquely identify the module in which each
callback subroutine is found, but it doesn't necessarily have to be so. Use
the package key any way you wish, or not at all:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { cb_key  => 'save',
                       cb      => \&My::World::save } ] );

But note that if you don't use the package key at all, you'll still need to
provide one in the field to be submitted to the Mason server. By default, that
key is "DEFAULT". Such a callback field in an HTML form would then look like
this:

  <input type="button" value="Save World" name="DEFAULT|save_cb" />

If you don't like the "DEFAULT" package name, you can set an alternative
default using the C<default_pkg_name> parameter to C<new()>:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key  => 'save',
                              cb      => \&My::World::save } ],
      default_pkg_name => 'MyPkg' );

Then, of course, any callbacks without a specified package key of their own
will then use the custom default:

  <input type="button" value="Save World" name="MyPkg|save_cb" />

=head3 Priority

Sometimes one callback is more important than another. For example, you might
rely on the execution of one callback to set up variables needed by another.
Since you can't rely on the order in which callbacks are executed (the Mason
request arguments are stored in a hash, and the processing of a hash is, of
course, unordered), you need a method of ensuring that the setup callback
executes first.

In such a case, you can set a higher priority level for the setup callback
than for callbacks that depend on it:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
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

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
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

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
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
C<post_callbacks> callback code references expect the same argument as
argument-triggered callbacks: a MasonX::CallbackHandleObject:

  sub foo {
      my $cbh = shift;
      # Do your business here.
  }

Of course, the attributes of the MasonX::CallbackHandleObject object will be
different than in argument-triggered callbacks. For example, the C<priority>,
C<pkg_key>, and C<cb_key> attributes will naturaly be undefined.

Like the argument-triggered callbacks, however, like the argument-triggered
callbacks, request callbacks are executed in a C<eval {}> block, so if any of
them C<die>s, an HTML::Mason::Exception::Callback::Execution exception will be
thrown.

=head1 INTERFACE

=head2 Parameters To The C<new()> Constructor

In addition to those offered by the HTML::Mason::ApacheHandler base class,
this module supports a number of its own parameters to the C<new()>
constructor.

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
should a single argument: a MasonX::CallbackHandle object.

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
executed for I<every> request I<before> any other callbacks. Each code
reference should expect a single MasonX::CallbackHandle argument. Use
pre-argument-triggered request callbacks when you want to do something with
the arguments sumitted for every request, such as convert character sets.

=item C<post_callbacks>

This parameter accepts an array reference of code references that should be
executed for I<every> request I<after> all other callbacks have been
called. Each code reference should expect a single MasonX::CallbackHandle
argument. Use post-argument-triggered request callbacks when you want to do
something with the arguments sumitted for every request, such as HTML-escape
their values.

=item C<default_priority>

The priority level at which callbacks will be executed. This value will be
used in each hash reference passed via the C<callbacks> parameter to C<new()>
that lacks a C<priority> key. You may specify a default priority level within
the range of "0" (highst priority) to "9" (lowest priority). If not specified,
it defaults to "5".

=item C<default_pkg_key>

The default package key for callbacks. This value that will be used in each
hash reference passed via the C<callbacks> parameter to C<new()> that lacks a
C<pkg_key> key. It can be any string that evaluates to a true value, and
defaults to "DEFAULT" if not specified.

=back

=head2 Accessor Methods

The properties C<default_priority> and C<default_pkg_key> have standard
read-only accessor methods of the same name. For example:

  my $cbah = new HTML::Mason::ApacheHandler::WithCallbacks;
  my $default_priority = $cbah->default_priority;
  my $default_pkg_key = $cbah->default_pkg_key;

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

Create object-oriented interface.

=item *

Figure out how to use F<httpd.conf> C<PerlSetVar> directives to pass callback
specs to C<new()>.

=item *

Add some good real-world examples to the documentation.

=back

=head1 SEE ALSO

L<MasonX::CallbackHandle|MasonX::CallbackHandle> objects get passed as the
sole argument to all callback code references, and offer access to data
relevant to the callback.

This module works with L<HTML::Mason|HTML::Mason> by subclassing
L<HTML::Mason::ApacheHandler|HTML::Mason::ApacheHandler>. Inspired by the
implementation of callbacks in Bricolage (L<http://bricolage.cc/>), it is
however a completely new code base with a rather different approach.

=head1 AUTHOR

David Wheeler <L<david@wheeler.net|"david@wheeler.net">>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
