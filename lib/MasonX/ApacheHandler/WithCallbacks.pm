package MasonX::ApacheHandler::WithCallbacks;

# $Id: WithCallbacks.pm,v 1.54 2003/07/26 16:32:28 david Exp $

use strict;
use HTML::Mason qw(1.10);
use HTML::Mason::ApacheHandler ();
use HTML::Mason::Exceptions ();
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

$VERSION = '1.00';

Params::Validate::validation_options
  ( on_fail => sub { HTML::Mason::Exception::Params->throw( join '', @_ ) } );

# We'll use this code reference for cb_classes parameter validation.
my $valid_cb_classes = sub {
    # Just return true if they use the string "ALL".
    return 1 if $_[0] eq 'ALL';
    # Return false if it isn't an array.
    return unless ref $_[0] || '' eq 'ARRAY';
    # Return true if the first value isn't the string "_ALL_";
    return 1 if $_[0]->[0] ne '_ALL_';
    # Return false if there's more than one element in the array.
    return if @{$_[0]} > 1;
    # Change the value from an array to "ALL"!
    $_[0] = 'ALL';
    return 1;
};

# We'll use this code reference to eval arguments passed in via httpd.conf
# PerlSetVar directives.
my $eval_directive = { convert => sub {
    return 1 if ref $_[0]->[0];
    for (@{$_[0]}) { $_ = eval $_ }
    return 1;
}};

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
      callbacks => $eval_directive,
      descr     => 'Callback specifications'
    },

    pre_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      optional  => 1,
      callbacks => $eval_directive,
      descr     => 'Callbacks to be executed before argument callbacks'
    },

    post_callbacks =>
    { type      => Params::Validate::ARRAYREF,
      parse     => 'list',
      optional  => 1,
      callbacks => $eval_directive,
      descr     => 'Callbacks to be executed after argument callbacks'
    },

    cb_classes =>
    { type      => Params::Validate::ARRAYREF | Params::Validate::SCALAR,
      parse     => 'list',
      callbacks => { 'valid cb_classes' => $valid_cb_classes },
      optional  => 1,
      descr     => 'List of calback classes from which to load callbacks'
    },

    exec_null_cb_values =>
    { type      => Params::Validate::BOOLEAN,
      parse     => 'boolean',
      default   => 1,
      descr     => 'Execute callbacks with null values'
    },

  );

BEGIN {
    require MasonX::CallbackHandler;
    MasonX::CallbackHandler::_find_names();
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    # Grab any class callback specifications.
    @{$self}{qw(_cbs _pre _post)} =
      MasonX::CallbackHandler->_load_classes($self->{cb_classes})
      if $self->{cb_classes};

    # Process argument-triggered callback specs.
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
              ) if $self->{_cbs}{$spec->{pkg_key}}->{$spec->{cb_key}};

            # Set it up.
            $self->{_cbs}{$spec->{pkg_key}}->{$spec->{cb_key}} =
              { cb => $spec->{cb}, priority => $spec->{priority} };
        }
    }

    # Now validate and store any global callbacks.
    foreach my $type (qw(pre post)) {
        if (my $cbs = delete $self->{$type . '_callbacks'}) {
            my @gcbs;
            foreach my $cb (@$cbs) {
                # Make it an array unless MasonX::CallbackHandler has already
                # done so.
                $cb = [$cb, 'MasonX::CallbackHandler']
                  unless ref $cb eq 'ARRAY';
                # Make sure that we have a code reference.
                HTML::Mason::Exception::Params->throw
                  ( error => "Global $type callback not a code reference" )
                  unless ref $cb->[0] eq 'CODE';
                push @gcbs, $cb;
            }
            # Keep 'em.
            $self->{"_$type"} = \@gcbs;
        }
    }

    # Warn 'em if they're not using any callbacks.
    unless ($self->{_cbs} or $self->{_pre} or $self->{_post}
            or $Apache::Server::Starting) {
        require Carp;
        Carp::carp("You didn't specify any callbacks. If you're not going " .
          "to use callbacks, you might as well just use " .
          "HTML::Mason::ApacheHandler.");
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
    my (@cbs, %cbhs);
    if ($self->{_cbs}) {
        foreach my $k (keys %$args) {
            # Strip off the '.x' that an <input type="image" /> tag creates.
            (my $chk = $k) =~ s/\.x$//;
            if ((my $key = $chk) =~ s/_cb(\d?)$//) {
                # It's a callback field. Grab the priority.
                my $priority = $1;

                # Skip callbacks without values, if necessary.
                next unless $self->{exec_null_cb_values} ||
                  (defined $args->{$k} && $args->{$k} ne '');

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
                my $cb;
                my $class = $self->{_cbs}{$pkg_key} or
                  HTML::Mason::Exception::Callback::InvalidKey->throw
                    ( error   => "No such callback package '$pkg_key'",
                      callback_key => $chk );

                if (ref $class) {
                    # It's a functional callback. Grab it.
                    $cb = $class->{$cb_key}{cb} or
                      HTML::Mason::Exception::Callback::InvalidKey->throw
                        ( error   => "No callback found for callback key '$chk'",
                          callback_key => $chk );

                    # Get the specified priority if none was included in the
                    # callback key.
                    $priority = $class->{$cb_key}{priority}
                      unless $priority ne '';
                    $class = 'MasonX::CallbackHandler';
                } else {
                    # It's a method callback. Get it from the class.
                    $cb = $class->_get_callback($cb_key, \$priority) or
                      HTML::Mason::Exception::Callback::InvalidKey->throw
                        ( error   => "No callback found for callback key '$chk'",
                          callback_key => $chk );
                }

                # Push the callback onto the stack, along with the parameters
                # for the construction of the  MasonX::CallbackHandler object
                # that will be passed to it.
                $cbhs{$class} ||= $class->new( request_args => $args,
                                               apache_req   => $r,
                                               ah           => $self,
                                             );
                push @{$cbs[$priority]},
                  [ $cb, $cbhs{$class},
                    [ $priority, $cb_key, $pkg_key, $chk, $args->{$k} ]
                  ];
            }
        }
    }

    # Put any pre and post callbacks onto the stack.
    if ($self->{_pre} or $self->{_post}) {
        my $params = [ request_args => $args,
                       apache_req   => $r,
                       ah           => $self ];
        unshift @cbs,
          [ map { [ $_->[0], $cbhs{$_} || $_->[1]->new(@$params), [] ] }
            @{$self->{_pre}} ]
          if $self->{_pre};

        push @cbs,
          [ map { [ $_->[0], $cbhs{$_} || $_->[1]->new(@$params), [] ] }
            @{$self->{_post}} ]
          if $self->{_post};
    }

    # Now execute the callbacks.
    eval {
        foreach my $cb_list (@cbs) {
            # Skip it if there are no callbacks for this priority.
            next unless $cb_list;
            foreach my $cb_data (@$cb_list) {
                my ($cb, $cbh, $cbargs) = @$cb_data;
                # Cheat! But this keeps them read-only for the client.
                @{$cbh}{qw(priority cb_key pkg_key trigger_key value)} =
                  @$cbargs;
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
    # Clean out the redirected attribute for the next request.
    delete $self->{redirected};
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

MasonX::ApacheHandler::WithCallbacks - Functional and object-oriented Mason callback architecture

=head1 SYNOPSIS

In your Mason component:

  % if (exists $ARGS{answer}) {
  <p><b>Answer: <% $ARGS{answer} %></b></p>
  % } else {
  <form>
    <p>Enter an epoch time: <input type="text" name="epoch_time" /><br />
      <input type="submit" name="myCallbacker|calc_time_cb" value="Calculate" />
    </p>
  </form>
  % }

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
    ( callbacks => [ { cb_key  => 'calc_time',
                       pkg_key => 'myCallbacker',
                       cb      => \&calc_time } ]
    );

  sub handler {
      my $r = shift;
      $ah->handle_request($r);
  }

Or, in a subclass of MasonX::CallbackHandler:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass( class_key => 'myCallbacker' );

  sub calc_time : Callback {
      my $self = shift;
      my $args = $self->request_args;
      my $val = $cbh->value;
      $args->{answer} = localtime($val || time);
  }

And then, in F<handler.pl>:

  # Load order is important here!
  use MyApp::CallbackHandler;
  use MasonX::ApacheHandler::WithCallbacks;

  my $ah = MasonX::ApacheHandler::WithCallbacks->new
    ( cb_classes => [qw(myCallbacker)] );

  sub handler {
      my $r = shift;
      $ah->handle_request($r);
  }

=begin comment

=head1 ABSTRACT

MasonX::ApacheHandler::WithCallbacks subclasses HTML::Mason::ApacheHandler in
order to provide functional and object-oriented callbacks. Callbacks are
executed at the beginning of a request, just before Mason creates and executes
the request component stack.

=end comment

=head1 DESCRIPTION

MasonX::ApacheHandler::WithCallbacks subclasses HTML::Mason::ApacheHandler in
order to provide a Mason callback system. Callbacks may be either code
references provided to the C<new()> constructor, or methods defined in
subclasses of MasonX::CallbackHandler. Callbacks are triggered either for
every request or by specially named keys in the Mason request arguments, and
all callbacks are executed at the beginning of a request, just before Mason
creates and executes the request component stack.

The idea behind this module is to provide a sort of plugin architecture for
Mason. Mason then executes code before executing any components. This approach
allows you to carry out logical processing of data submitted from a form, to
affect the contents of the Mason request arguments (and thus the C<%ARGS> hash
in components), and even to redirect or abort the request before Mason handles
it.

=head1 JUSTIFICATION

Why would you want to do this? Well, there are a number of reasons. Some I can
think of offhand include:

=over 4

=item Stricter separation of logic from presentation

Most application logic handled in Mason components takes place in
C<< <%init> >> blocks, often in the same component as presentation logic. By
moving the application logic into Perl modules and then directing Mason to
execute that code as callbacks, you obviously benefit from a cleaner
separation of application logic and presentation.

=item Widgitization

Thanks to their ability to preprocess arguments, callbacks enable developers
to develop easier-to-use, more dynamic widgets that can then be used in any
and all Mason component. For example, a widget that puts many related fields
into a form (such as a date selection widget) can have its fields preprocessed
by a callback (for example, to properly combine the fields into a unified date
field) before the Mason component that responds to the form submission gets
the data. See L<MasonX::CallbackHandler|MasonX::CallbackHandler/"Subclassing
Examples"> for an example solution for this very problem.

=item Shared Memory

Callbacks are just Perl subroutines in modules loaded at server startup time.
Thus the memory they consume is all in the Apache parent process, and shared
by the child processes. For code that executes frequently, this can be much
less resource-intensive than code in Mason components, since components are
loaded separately in each Apache child process (unless they're preloaded via
the C<preloads> parameter to the HTML::Mason::Interp constructor).

=item Performance

Since they're executed before Mason creates a component stack and executes the
components, callbacks have the opportunity to short-circuit the Mason
processing by doing something else. A good example is redirection. Often the
application logic in callbacks does its thing and then redirects the user to a
different page. Executing the redirection in a callback eliminates a lot of
extraneous processing that would otherwise be executed before the redirection,
creating a snappier response for the user.

=item Testing

Mason components are not easy to test via a testing framework such as
Test::Harness. Subroutines in modules, on the other hand, are fully
testable. This means that you can write tests in your application test suite
to test your callback subroutines. See
L<MasonX::CallbackTester|MasonX::CallbackTester> for details.

=back

And if those aren't enough reasons, then just consider this: Callbacks are
just I<way cool.>

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
how to configure a functional callback when constructing your
MasonX::ApacheHandler::WithCallbacks object so that that doesn't happen:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks => [ { pkg_key => 'world',
                       cb_key  => 'save',
                       cb      => \&My::World::save } ] );

With this configuration, the request argument created by the above HTML form
field will trigger the execution of the C<&My::World::save> subroutine.

=head3 Functional Callback Subroutines

Functional callbacks use a code reference for argument-triggered callbacks,
and MasonX::ApacheHandler::WithCallbacks executes them with a single argument,
a MasonX::CallbackHandler object. Thus, a callback subroutine will generally
look something like this:

  sub foo {
      my $cbh = shift;
      # Do stuff.
  }

The MasonX::CallbackHandler object provides accessors to data relevant to the
callback, including the callback key, the package key, and the request
arguments. It also includes C<redirect()> and C<abort()> methods. See the
L<MasonX::CallbackHandler|MasonX::CallbackHandler> documentation for all the
goodies.

Note that all callbacks are executed in a C<eval {}> block, so if any of your
callback subroutines C<die>, MasonX::ApacheHandler::WithCallbacks will
throw an HTML::Mason::Exception::Callback::Execution exception.

=head3 Object-Oriented Callback Methods

Object-oriented callback methods are defined in subclasses of
MasonX::CallbackHandler. Unlike functional callbacks, they are not called with
a MasonX::CallbackHandler object, but with an instantiation of the callback
subclass. These classes inherit all the goodies provided by
MasonX::CallbackHandler, so you can essentially use their instances exactly as
you would use the MasonX::CallbackHandler object in functional callback
subroutines. But because they're subclasses, you can add your own methods and
attributes. See L<MasonX::CallbackHandler|MasonX::CallbackHandler> for all the
gory details on subclassing, along with a few examples. Generally, callback
methods will look like this:

  sub foo : Callback {
      my $self = shift;
      # Do stuff.
  }

As with functional callback subroutines, method callbacks are executed in a
C<eval {}> block, so the same caveats apply.

B<Note:> It's important that you C<use> any and all MasonX::Callback
subclasses I<before> you C<use MasonX::ApacheHandler::WithCallbacks>. This is
to get around an issue with identifying the names of the callback methods in
mod_perl. Read the comments in the MasonX::Callback source code if you're
interested in learning more.

=head3 The Package Key

The use of the package key is a convenience so that a system with many
functional callbacks can use callbacks with the same keys but in different
packages. The idea is that the package key will uniquely identify the module
in which each callback subroutine is found, but it doesn't necessarily have to
be so. Use the package key any way you wish, or not at all:

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

=head3 The Class Key

The class key is essentially a synonym for the package key, but applies more
directly to object-oriented callbacks. The difference is mainly that it
corresponds to an actual class, and that all MasonX::CallbackHandler
subclasses are I<required> to have a class key; it's not optional as it is
with functional callbacks. The class key may be declared in your
MasonX::CallbackHandler subclass like so:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass( class_key => 'MyCBHandler' );

The class key can also be declared by implementing a C<CLASS_KEY()> method,
like so:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass;
  use constant CLASS_KEY => 'MyCBHandler';

If no class key is explicitly defined, MasonX::CallbackHandler will use the
subclass name, instead. In any event, the C<register_callback()> method
B<must> be called to register the subclass with MasonX::CallbackHandler. See
the L<MasonX::CallbackHandler|MasonX::CallbackHandler/"Callback Class
Declaration"> documentation for complete details.

=head3 Priority

Sometimes one callback is more important than another. For example, you might
rely on the execution of one callback to set up variables needed by another.
Since you can't rely on the order in which callbacks are executed (the Mason
request arguments are stored in a hash, and the processing of a hash is, of
course, unordered), you need a method of ensuring that the setup callback
executes first.

In such a case, you can set a higher priority level for the setup callback
than for callbacks that depend on it. For functional callbacks, you can do it
like this:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key   => 'setup',
                              priority => 3,
                              cb       => \&setup },
                            { cb_key   => 'save',
                              cb       => \&save }
                          ] );

For object-oriented callbacks, you can define the priority right in the
callback method declaration:

  sub setup : Callback( priority => 3 ) {
      my $self = shift;
      # ...
  }

  sub save : Callback {
      my $self = shift;
      # ...
  }

In these examples, the "setup" callback has been configured with a priority
level of "3". This ensures that it will always execute before the "save"
callback, which has the default priority of "5". This is true regardless of
the order of the fields in the corresponding HTML::Form:

  <input type="button" value="Save World" name="DEFAULT|save_cb" />
  <input type="hidden" name="DEFAULT|setup_cb" value="1" />

Despite the fact that the "setup" callback field appears after the "save"
field (and will generally be submitted by the browser in that order), the
"setup" callback will always execute first because of its higher priority.

Although the "save" callback got the default priority of "5", this too can be
customized to a different priority level via the C<default_priority> parameter
to C<new()> for functional callbacks and the C<default_priority> to the class
declaration for object-oriented callbacks For example, this functional
callback configuration:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( callbacks        => [ { cb_key   => 'setup',
                              priority => 3,
                              cb       => \&setup },
                            { cb_key   => 'save',
                              cb       => \&save }
                          ],
      default_priority => 2 );

And this MasonX::CallbackHandler subclass declaration:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass( class_key => 'MyCBHandler',
                                  default_priority => 2 );

Will cause the "save" callback to always execute before the "setup" callback,
since its priority level will default to "2".

In addition, the priority level can be overridden via the form submission field
itself by appending a priority level to the end of the callback field
name. Hence, this example:

  <input type="button" value="Save World" name="DEFAULT|save_cb2" />
  <input type="hidden" name="DEFAULT|setup_cb" value="1" />

Causes the "save" callback to execute before the "setup" callback by
overriding the "save" callback's priority to level "2". Of course, any other
form field that triggers the "save" callback without a priority override will
still execute "save" at its configured level.

=head2 Request Callbacks

Request callbacks come in two separate flavors: those that execute before the
argument-triggered callbacks, and those that execute after the
argument-triggered callbacks. All of them execute before the Mason component
stack executes. Functional request callbacks may be specified via the
C<pre_callbacks> and C<post_callbacks> parameters to C<new()>, respectively:

  my $cbah = MasonX::ApacheHandler::WithCallbacks->new
    ( pre_callbacks  => [ \&translate, \&foobarate ],
      post_callbacks => [ \&escape, \&negate ] );

Object-oriented request callbacks may be declared via the C<PreCallback> and
C<PostCallback> method attributes, like so:

  sub translate : PreCallback { ... }
  sub foobarate : PreCallback { ... }
  sub escape : PostCallback { ... }
  sub negate : PostCallback { ... }

In these examples, the C<translate()> and C<foobarate()> subroutines or
methods will execute (in that order) before any argument-triggered callbacks
are executed (none will be in these examples, since none are specified).

Conversely, the C<escape()> and C<negate()> subroutines or methods will be
executed (in that order) after all argument-triggered callbacks have been
executed. And regardless of what argument-triggered callbacks may be
triggered, the request callbacks will always be executed for I<every> request.

Although they may be used for different purposes, the C<pre_callbacks> and
C<post_callbacks> functional callback code references expect the same argument
as argument-triggered functional callbacks: a MasonX::CallbackHandler object:

  sub foo {
      my $cbh = shift;
      # Do your business here.
  }

Similarly, object-oriented request callback methods will be passed an object
of the class defined in the class key portion of the callback trigger --
either an object of the class in which the callback is defined, or an object
of a subclass:

  sub foo : PostCallback {
      my $self = shift;
      # ...
  }

Of course, the attributes of the MasonX::CallbackHandler or subclass object
will be different than in argument-triggered callbacks. For example, the
C<priority>, C<pkg_key>, and C<cb_key> attributes will naturally be
undefined. It will, however, be the same instance of the object passed to all
other functional callbacks -- or to all other class callbacks with the same
class key -- in a single request.

Like the argument-triggered callbacks, request callbacks are executed in a
C<eval {}> block, so if any of them C<die>s, an
HTML::Mason::Exception::Callback::Execution exception will be thrown.

=head1 INTERFACE

=head2 Parameters To The C<new()> Constructor

In addition to those offered by the HTML::Mason::ApacheHandler base class,
this module supports a number of its own parameters to the C<new()>
constructor. Each also has a corresponding F<httpd.conf> variable, as well,
so, if you really want to, you can use MasonX::ApacheHandler::WithCallbacks
right in your F<httpd.conf> file:

  PerlModule MasonX::ApacheHandler::WithCallbacks
  SetHandler perl-script
  PerlHandler MasonX::ApacheHandler::WithCallbacks

The parameters to C<new()> and their corresponding F<httpd.conf> variables are
as follows:

=over 4

=item C<callbacks>

Argument-triggered functional callbacks are configured via the C<callbacks>
parameter. This parameter is an array reference of hash references, and each
hash reference specifies a single callback. The supported keys in the callback
specification hashes are:

=over 4

=item C<cb_key>

Required. A string that, when found in a properly-formatted Mason request
argument key, will trigger the execution of the callback.

=item C<cb>

Required. A reference to the Perl subroutine that will be executed when the
C<cb_key> has been found in a Mason request argument key. Each code reference
should expect a single argument: a MasonX::CallbackHandler object. The same
instance of a MasonX::CallbackHandler object will be used for all functional
callbacks in a single request.

=item C<pkg_key>

Optional. A key to uniquely identify the package in which the callback
subroutine is found. This parameter is useful in systems with many callbacks,
where developers may wish to use the same C<cb_key> for different subroutines
in different packages. The default package key may be set via the
C<default_pkg_key> parameter.

=item C<priority>

Optional. Indicates the level of priority of a callback. Some callbacks are
more important than others, and should be executed before the others.
MasonX::ApacheHandler::WithCallbacks supports priority levels ranging from
"0" (highest priority) to "9" (lowest priority). The default priority for
functional callbacks may be set via the C<default_priority> parameter.

=back

The <callbacks> parameter can also be specified via the F<httpd.conf>
configuration variable C<MasonCallbacks>. Use C<PerlSetVar> to specify
several callbacks; each one should be an C<eval>able string that converts into
a hash reference as specified here. For example, to specify two callbacks, use
this syntax:

  PerlAddVar MasonCallbacks "{ cb_key  => 'foo', cb => sub { ... }"
  PerlAddVar MasonCallbacks "{ cb_key  => 'bar', cb => sub { ... }"

Note that the C<eval>able string must be entirely on its own line in the
F<httpd.conf> file.

=item C<pre_callbacks>

This parameter accepts an array reference of code references that should be
executed for I<every> request I<before> any other callbacks. They will be
executed in the order in which they're listed in the array reference. Each
code reference should expect a single MasonX::CallbackHandler argument. The
same instance of a MasonX::CallbackHandler object will be used for all
functional callbacks in a single request. Use pre-argument-triggered request
callbacks when you want to do something with the arguments submitted for every
request, such as convert character sets.

The <pre_callbacks> parameter can also be specified via the F<httpd.conf>
configuration variable C<MasonPreCallbacks>. Use multiple C<PerlAddVar> to
add multiple pre-request callbacks; each one should be an C<eval>able string
that converts into a code reference:

  PerlAddVar MasonPreCallbacks "sub { ... }"
  PerlAddVar MasonPreCallbacks "sub { ... }"

=item C<post_callbacks>

This parameter accepts an array reference of code references that should be
executed for I<every> request I<after> all other callbacks have been called.
They will be executed in the order in which they're listed in the array
reference. Each code reference should expect a single MasonX::CallbackHandler
argument. The same instance of a MasonX::CallbackHandler object will be used
for all functional callbacks in a single request. Use post-argument-triggered
request callbacks when you want to do something with the arguments submitted
for every request, such as HTML-escape their values.

The <post_callbacks> parameter can also be specified via the F<httpd.conf>
configuration variable C<MasonPostCallbacks>. Use multiple C<PerlAddVar> to
add multiple post-request callbacks; each one should be an C<eval>able string
that converts into a code reference:

  PerlAddVar MasonPostCallbacks "sub { ... }"
  PerlAddVar MasonPostCallbacks "sub { ... }"

=item C<cb_classes>

An array reference listing the class keys of all of the
MasonX::CallbackHandler subclasses containing callback methods that you want
included in your MasonX::ApacheHandler::WithCallbacks object. Alternatively,
the C<cb_classes> parameter may simply be the word "ALL", in which case I<all>
MasonX::CallbackHandler subclasses will have their callback methods registered
with your MasonX::ApacheHandler::WithCallbacks object. See the
L<MasonX::CallbackHandler|MasonX::CallbackHandler> documentation for details
on creating callback classes and methods.

B<Note:> Be sure to C<use MasonX::ApacheHandler::WithCallbacks> I<only> after
you've C<use>d all of the MasonX::CallbackHandler subclasses you need or else
you won't be able to use their callback methods.

The <cb_classes> parameter can also be specified via the F<httpd.conf>
configuration variable C<MasonCbClasses>. Use multiple C<PerlAddVar> to add
multiple callback class keys. But, again, be sure to load
MasonX::ApacheHandler::WithCallbacks> I<only> after you've loaded all of your
MasonX::Callback handler subclasses:

  PerlModule My::CBClass
  PerlModule Your::CBClass
  PerlSetVar MasonCbClasses myCBClass
  PerlAddVar MasonCbClasses yourCBClass
  # Load MasonX::ApacheHandler::WithCallbacks last!
  PerlModule MasonX::ApacheHandler::WithCallbacks

=item C<default_priority>

The priority level at which functional callbacks will be executed. Does not
apply to object-oriented callbacks. This value will be used in each hash
reference passed via the C<callbacks> parameter to C<new()> that lacks a
C<priority> key. You may specify a default priority level within the range of
"0" (highest priority) to "9" (lowest priority). If not specified, it defaults
to "5".

Use the C<MasonDefaultPriority> variable to set the the C<default_priority>
parameter in your F<httpd.conf> file:

  PerlSetVar MasonDefaultPriority 3

=item C<default_pkg_key>

The default package key for functional callbacks. Does not apply to
object-oriented callbacks. This value that will be used in each hash reference
passed via the C<callbacks> parameter to C<new()> that lacks a C<pkg_key>
key. It can be any string that evaluates to a true value, and defaults to
"DEFAULT" if not specified.

Use the C<MasonDefaultPkgKey> variable to set the the C<default_pkg_key>
parameter in your F<httpd.conf> file:

  PerlSetVar MasonDefaultPkgKey CBFoo

=item C<exec_null_cb_values>

Be default, MasonX::ApacheHandler::WithCallbacks will execute all request
callbacks. However, in many situations it may be desireable to skip any
callbacks that have no value for the callback field. One can do this by simply
checking C<< $cbh->value >> in the callback, but if you need to disable the
execution of all callbacks, pass the C<exec_null_cb_value> parameter with a
false value. It is set to a true value by default.

Use the C<MasonExecNullCbValues> variable to set the the
C<exec_null_cb_values> parameter in your F<httpd.conf> file:

  PerlSetVar MasonExecNullCbValues 0

B<Note:> The default value of this parameter may be changed to false in a
future release. Feedback welcome.

=back

=head2 Accessor Methods

The properties C<default_priority> and C<default_pkg_key> have standard
read-only accessor methods of the same name. For example:

  my $cbah = new HTML::Mason::ApacheHandler::WithCallbacks;
  my $default_priority = $cbah->default_priority;
  my $default_pkg_key = $cbah->default_pkg_key;

=head1 ACKNOWLEDGMENTS

Garth Webb implemented the original callbacks in Bricolage, based on an idea
he borrowed from Paul Lindner's work with Apache::ASP. My thanks to them both
for planting this great idea!

=head1 TODO

=over 4

=item *

Change it to a subclass of HTML::Mason::Request. This will require that we
override that class' C<exec()> method, and that we override C<new()> to call
C<alter_superclass()> to do the right thing. See MasonX::Request::WithSession
for an example. Figure out what to do about the redirect() method in
CallbackHandler.

=item *

Generalize for use with other templating systems. Start with Template Toolkit
by subclassing Template.pm and overriding its C<process()> method. Do the same
for HTML::Template by overriding its C<output()> method. Maybe Later add in
Embperl and Apache::ASP. Will likely have to move the argument processing code
into an independent namespace. The code for registering callbacks should be
able to remain largely the same, however.

=back

=head1 BUGS

Please report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MasonX-ApacheHandler-WithCallbacks>.

=head1 SEE ALSO

L<MasonX::CallbackHandler|MasonX::CallbackHandler> objects get passed as the
sole argument to all functional callbacks, and offer access to data relevant
to the callback. MasonX::CallbackHandler also defines the object-oriented
callback interface, making its documentation a must-read for anyone who wishes
to create callback classes and methods.

Use L<MasonX::CallbackTester|MasonX::CallbackTester> to test your callback
packages and classes.

This module works with L<HTML::Mason|HTML::Mason> by subclassing
L<HTML::Mason::ApacheHandler|HTML::Mason::ApacheHandler>. Inspired by the
implementation of callbacks in Bricolage (L<http://bricolage.cc/>), it is
however a completely new code base with a rather different approach.

=head1 AUTHOR

David Wheeler <david@wheeler.net>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
