package MasonX::CallbackHandler;

use strict;
use HTML::Mason::Exceptions ();
use Apache::Constants qw(REDIRECT);
use Class::Container ();

BEGIN {
    # The object-oriented interface is only supported with the use of
    # Attribute::Handlers in Perl 5.6 and later. We'll use Class::ISA
    # to get a list of all the classes that a class inherits from so
    # that we can tell ApacheHandler::WithCallbacks that they exist and
    # are loaded.
    unless ($] < 5.006) {
        require Attribute::Handlers;
        require Class::ISA;
    }
}

use HTML::Mason::MethodMaker( read_only => [qw(ah
                                               request_args
                                               apache_req
                                               priority
                                               cb_key
                                               pkg_key
                                               trigger_key
                                               value)] );
*class_key = \&pkg_key;

use vars qw($VERSION @ISA);
@ISA = qw(Class::Container);

$VERSION = '0.98';
use constant DEFAULT_PRIORITY => 5;

Params::Validate::validation_options
  ( on_fail => sub { HTML::Mason::Exception::Params->throw( join '', @_ ) } );

my $is_num = { 'valid priority' => sub { $_[0] =~ /^\d$/ } };
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
      callbacks => $is_num,
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

##############################################################################
# Subclasses must use register_subclass() to register the subclass. They can
# also use it to set up the class key and a default priority for the subclass,
# But base class CLASS_KEY() and DEFAULT_PRIORITY() methods can also be
# overridden to do that.
my (%priorities, %classes, %pres, %posts, @reqs, %isas, @classes);
sub register_subclass {
    shift; # Not needed.
    my $class = caller;
    return unless UNIVERSAL::isa($class, __PACKAGE__)
      and $class ne __PACKAGE__;
    my $spec = { default_priority =>
                 { type      => Params::Validate::SCALAR,
                   optional  => 1,
                   callbacks => $is_num
                 },
                 class_key =>
                 { type      => Params::Validate::SCALAR,
                   optional  => 1
                 },
               };

    my %p = Params::Validate::validate(@_, $spec);

    # Grab the class key. Default to the actual class name.
    my $ckey = $p{class_key} || $class;

    # Create the CLASS_KEY method if it doesn't exist already.
    unless (defined &{"$class\::CLASS_KEY"}) {
        no strict 'refs';
        *{"$class\::CLASS_KEY"} = sub { $ckey };
    }
    $classes{$class->CLASS_KEY} = $class;

    if (defined $p{default_priority}) {
        # Override any base class DEFAULT_PRIORITY methods.
        no strict 'refs';
        *{"$class\::DEFAULT_PRIORITY"} = sub { $p{default_priority} };
    }

    # Push the class into an array so that we can be sure to process it in
    # the proper order later.
    push @classes, $class;
}

##############################################################################

# This method is called by subclassed methods that want to be
# argument-triggered callbacks.

sub Callback : ATTR(CODE, BEGIN) {
    my ($class, $symbol, $coderef, $attr, $data, $phase) = @_;
    # Validate the arguments. At this point, there's only one allowed,
    # priority. This is to set a priority for the callback method that
    # overrides that set for the class.
    my $spec = { priority =>
                 { type      => Params::Validate::SCALAR,
                   optional  => 1,
                   callbacks => $is_num
                 },
               };
    my %p = Params::Validate::validate(@$data, $spec);
    # Get the priority.
    my $priority = $p{priority} || $class->DEFAULT_PRIORITY;
    # Store the priority under the code reference.
    $priorities{$coderef} = $priority;
}

##############################################################################

# These methods are called by subclassed methods that want to be request
# callbacks.

sub PreCallback : ATTR(CODE, BEGIN) {
    my ($class, $symbol, $coderef) = @_;
    # Store a reference to the code in a temporary location and a pointer to
    # it in the array.
    push @reqs, $coderef;
    push @{$pres{$class}->{__TMP}}, $#reqs;
}

sub PostCallback : ATTR(CODE, BEGIN) {
    my ($class, $symbol, $coderef) = @_;
    # Store a reference to the code in a temporary location and a pointer to
    # it in the array.
    push @reqs, $coderef;
    push @{$posts{$class}->{__TMP}}, $#reqs;
}

##############################################################################
# This method is called by MasonX::ApacheHandler::WithCallbacks to find the
# names of all the callback methods declared with the PreCallback and
# PostCallback attributes (might handle those declared with the Callback
# attribute at some point, as well -- there's some of it in CVS Revision
# 1.21). This is necessary because, in a BEGIN block, the symbol isn't defined
# when the attribute callback is called. I would use a CHECK or INIT block,
# but mod_perl ignores them. So the solution is to have the callback methods
# save the code references for the methods, make sure that
# MasonX::ApacheHandler::WithCallbacks is loaded _after_ all the classes that
# inherit from MasonX::CallbackHandler, and have it call this method to go
# back and find the names of the callback methods. The method names will then
# of course be used for the callback names. In mod_perl2, we'll likely be able
# to call this method from a PerlPostConfigHandler instead of making
# ApacheHandler::WithCallbacks do it, thus relieving the enforced loading
# order.
# http://perl.apache.org/docs/2.0/user/handlers/server.html#PerlPostConfigHandler

sub _find_names {
    foreach my $class (@classes) {
        # Find the names of the request callback methods.
        foreach my $type (\%pres, \%posts) {
            # We've stored an index pointing to each method in the @reqs
            # array under __TMP PreCallback() and PostCallback().
            if (my $idxs = delete $type->{$class}{__TMP}) {
                foreach my $idx (@$idxs) {
                    my $code = $reqs[$idx];
                    # Grab the symbol hash for this code reference.
                    my $sym = Attribute::Handlers::findsym($class, $code)
                      or die "Anonymous subroutines not supported. Make sure that " .
                        "MasonX::ApacheHandler::WithCallbacks loads last";
                    # ApacheHandler::WithCallbacks wants this array reference.
                    $type->{$class}{*{$sym}{NAME}} = [ sub { goto $code }, $class ];
                }
            }
        }
        # Copy any request callbacks from their parent classes. This is to
        # ensure that rquest callbacks act like methods, even though,
        # technically, they're not.
        $isas{$class} = _copy_meths($class);
    }
     # We don't need these anymore.
    @classes = ();
    @reqs = ();
}

##############################################################################
# This little gem, called by _find_names(), mimics inheritance by copying the
# request callback methods declared for parent class keys into the children.
# Any methods declared in the children will, of course, override. This means
# that the parent methods can never actually be called, since request
# callbacks are called for every request, and thus don't have a class
# association. They still get the correct object passed as their first
# parameter, however.
sub _copy_meths {
    my $class = shift;
    my %seen;
    # Grab all of the super classes.
    foreach my $super (grep { UNIVERSAL::isa($_, __PACKAGE__) }
                       Class::ISA::super_path($class)) {
        # Skip classes we've already seen.
        unless ($seen{$super}) {
            # Copy request callback code references.
            foreach my $type (\%pres, \%posts) {
                if ($type->{$class} and $type->{$super}) {
                    # Copy the methods, but allow newer ones to override.
                    $type->{$class} = { %{ $type->{$super} },
                                        %{ $type->{$class} }
                                      };
                } elsif ($type->{$super}) {
                    # Just copy the methods.
                    $type->{$class} = { %{ $type->{$super} }};
                }
            }
            $seen{$super} = 1;
        }
    }

    # Return an array ref of the super classes.
    return [keys %seen];
}

##############################################################################
# This method is called by MasonX::ApacheHandler::WithCallbacks to find
# methods for callback classes. This is because MasonX::CallbackHandler stores
# this list of callback classes, not MasonX::ApacheHandler::WithCallbacks.
# Its arguments are the callback class, the name of the method (callback),
# and a reference to the priority. We'll only assign the priority if it
# hasn't been assigned one already -- that is, it hasn't been _called_ with
# a priority.

sub _get_callback {
    my ($class, $meth, $p) = @_;
    # Get the callback code reference.
    my $c = UNIVERSAL::can($class, $meth) or return;
    # Get the priority for this callback. If there's no priority, it's not
    # a callback, so skip it.
    my $priority = $priorities{$c} or return;
    # Reformat the callback code reference.
    my $code = sub { goto $c };
    # Assign the priority, if necessary.
    $$p = $priority unless $$p ne '';
    # Create and return the callback.
    return $code;
}

##############################################################################
# This method is also called by MasonX::ApacheHandler::WithCallbacks, where
# the cb_classes parameter passes in a list of callback class keys or the
# string "ALL" to indicate that all of the callback classes should have their
# callbacks loaded for use by the ApacheHandler.

sub _load_classes {
    my ($pkg, $ckeys) = @_;
    # Just return success if there are no classes to be loaded.
    return unless defined $ckeys;
    my ($cbs, $pres, $posts);
    # Process the class keys in the order they're given, or just do all of
    # them if $ckeys eq 'ALL' (checked by ApacheHandler::WithCallbacks).
    foreach my $ckey (ref $ckeys ? @$ckeys : keys %classes) {
        my $class = $classes{$ckey} or
          die "Class with class key '$ckey' not loaded. Did you forget use"
            . " it or to call register_subclass()?";
        # Map the class key to the class for the class and all of its parent
        # classes, all for the benefit of ApacheHandler::WithCallbacks.
        $cbs->{$ckey} = $class;
        foreach my $c (@{$isas{$class}}) {
            next if $c eq __PACKAGE__;
            $cbs->{$c->CLASS_KEY} = $c;
        }
        # Load request callbacks in the order they're defined. Methods
        # inherited from parents have already been copied, so don't worry
        # about them.
        push @$pres, values %{ $pres{$class} } if $pres{$class};
        push @$posts, values %{ $posts{$class} } if $posts{$class};
    }
    return ($cbs, $pres, $posts);
}

##############################################################################

sub redirect {
    my ($self, $url, $wait, $status) = @_;
    $status ||= REDIRECT;
    my $r = $self->apache_req;
    $r->method('GET');
    $r->headers_in->unset('Content-length');
    $r->err_header_out( Location => $url );
    my $ah = $self->ah;
    # Should I use accessors here? Nah.
    $ah->{_status} = $status;
    $ah->{redirected} = $url;
    $self->abort($status) unless $wait;
}

##############################################################################

sub redirected { $_[0]->ah->redirected }

##############################################################################

sub abort {
    my ($self, $aborted_value) = @_;
    # Should I use an accessor here?
    $self->ah->{_status} = $aborted_value;
    HTML::Mason::Exception::Abort->throw
        ( error => ref $self . '->abort was called',
          aborted_value => $aborted_value );
}

##############################################################################

sub aborted {
    my ($self, $err) = @_;
    $err = $@ unless defined $err;
    return HTML::Mason::Exceptions::isa_mason_exception( $err, 'Abort' );
}

1;
__END__

=head1 NAME

MasonX::CallbackHandler - Mason callback request class and OO callback base class

=head1 SYNOPSIS

Functional callback interface:

  sub my_callback {
      my $cbh = shift;
      my $args = $cbh->request_args;
      my $value = $cbh->value;
      # Do stuff with above data.
      $cbh->redirect($url);
  }

Object-oriented callback interface:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  use constant CLASS_KEY => 'MyHandler';
  use strict;

  sub my_callback : Callback {
      my $self = shift;
      my $args = $self->request_args;
      my $value = $self->value;
      # Do stuff with above data.
      $self->redirect($url);
  }

=head1 DESCRIPTION

MasonX::CallbackHandler provides the interface for callbacks to access Mason
request arguments, the MasonX::ApacheHandler::WithCallbacks object, and
callback metadata, as well as for executing common request actions, such as
redirecting or aborting a request. There are two ways to use
MasonX::CallbackHandler: via functional-style callback subroutines and via
object-oriented callback methods.

For functional callbacks, a MasonX::CallbackHandler object is constructed by
MasonX::ApacheHandler::WithCallbacks for each request and passed in as the
sole argument for every execution of a callback function. See
L<MasonX::ApacheHandler::WithCallbacks|MasonX::ApacheHandler::WithCallbacks>
for details on how to configure Mason to execute your callback code.

In the object-oriented callback interface, MasonX::CallbackHandler is the
parent class from which all callback classes inherit. Callback methods are
declared in such subclasses via C<Callback>, C<PreCallback> and
C<PostCallback> attributes to each method declaration. Methods without one of
these callback attributes are not callback methods. Details on subclassing
MasonX::CallbackHandler may be found in the L<subclassing|"SUBCLASSING">
section.

=head1 INTERFACE

MasonX::CallbackHandler provides the request metadata accessors and utility
methods that will help manage a callback request. Functional callbacks always
get a MasonX::CallbackHandler object passed as their first argument; the same
MasonX::CallbackHandler object will be used for all callbacks in a single
request. For object-oriented callback methods, the first argument will of
course always be an object of the class corresponding to the class key used in
the callback key (or, for request callback methods, an instance of the class
for which the callback method was loaded), and the same object will be reused
for all subsequent callbacks to the same class in a single request.

=head2 Accessor Methods

All of the MasonX::CallbackHandler accessor methods are read-only. Feel free
to add other attributes in your MasonX::CallbackHandler subclasses if you're
using the object-oriented callback interface.

=head3 ah

  my $ah = $cbh->ah;

Returns a reference to the MasonX::ApacheHandler::WithCallbacks object that
executed the callback.

=head3 request_args

  my $args = $cbh->request_args;

Returns a reference to the Mason request arguments hash. This is the hash that
will be used to create the C<%ARGS> hash and the C<< <%args> >> block
variables in your Mason components. Any changes you make to this hash will
percolate back to your components, as well as to all subsequent callbacks
in the same request.

=head3 apache_req

  my $r = $cbh->apache_req;

Returns the Apache request object for the current request. If you've told
Mason to use L<Apache::Request|Apache::Request>, an Apache::Request object
that will be returned. Otherwise, if you're having CGI process your request
arguments, then it will be the plain old L<Apache|Apache> object.

=head3 priority

  my $priority = $cbh->priority;

Returns the priority level at which the callback was executed. Possible values
are between "0" and "9", and may be set by a default priority setting, by the
callback configuration or method declaration, or by the argument callback
trigger key. See
L<MasonX::ApacheHandler::WithCallbacks|MasonX::ApacheHandler::WithCallbacks>
for details.

=head3 cb_key

  my $cb_key = $cbh->cb_key;

Returns the callback key that triggered the execution of the callback. For
example, this callback-triggering form field:

  <input type="submit" value="Save" name="DEFAULT|save_cb" />

Will cause the C<cb_key()> method in the relevant callback to return "save".

=head3 pkg_key

  my $pkg_key = $cbh->pkg_key;

Returns the package key used in the callback trigger field. For example, this
callback-triggering form field:

  <input type="submit" value="Save" name="MyCBs|save_cb" />

Will cause the C<pkg_key()> method in the relevant callback to return "MyCBs".

=head3 class_key

  my $class_key = $cbh->class_key;

An alias for C<pkg_key>, only perhaps a bit more appealing for use in
object-oriented callback methods.

=head3 trigger_key

  my $trigger_key = $cbh->trigger_key;

Returns the request argument key that triggered the callback. This is the
complete name used in the HTML field that triggered the callback. For example,
if the field that triggered the callback looks like this:

  <input type="submit" value="Save" name="MyCBs|save_cb6" />

Then the value returned by C<trigger_key()> method will be "MyCBs|save_cb6".

B<Note:> Most browsers will submit "image" input fields with two arguments,
one with ".x" appended to its name, and the other with ".y" appended to its
name. MasonX::ApacheHandler::WithCallbacks will ignore these fields and either
use the field that's named without the ".x" or ".y", or create a field with
that name and give it a value of "1". The reasoning behind this approach is
that the names of the callback-triggering fields should be the same as the
names that appear in the HTML form fields. If you want the actual x and y
image click coordinates, access them directly from the request arguments:

  my $args = $cbh->request_args;
  my $trigger_key = $cbh->trigger_key;
  my $x = $args->{"$trigger_key.x"};
  my $y = $args->{"$trigger_key.y"};

=head3 value

  my $value = $cbh->value;

Returns the value of the callback trigger field. If there is more than one
value for the callback trigger field, then C<value()> will return an array
reference. For example, for this callback field:

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
to determine which value or values were submitted for a particular callback
execution. So MasonX::CallbackHandler kindly provides the value or values for
you. The exception to this rule is values submitted as part of an "image"
input field. See the note about this under the documentation for the
C<trigger_key()> method.

=head3 redirected

  $cbh->redirect($url) unless $cbh->redirected;

If the request has been redirected, this method returns the redirection
URL. Otherwise, it returns false. This method is useful for conditions in which
one callback has called C<< $cbh->redirect >> with the optional C<$wait>
argument set to a true value, thus allowing subsequent callbacks to continue
to execute. If any of those subsequent callbacks want to call
C<< $cbh->redirect >> themselves, they can check the value of
C<< $cbh->redirected >> to make sure it hasn't been done already.

=head2 Other Methods

MasonX::CallbackHandler offers has a few other publicly accessible methods.

=head3 redirect

  $cbh->redirect($url);
  $cbh->redirect($url, $status);
  $cbh->redirect($url, $status, $wait);

Given a URL, this method generates a proper HTTP redirect for that URL. By
default, the status code used is "302", but this can be overridden via the
C<$status> argument. If the optional C<$wait> argument is true, any callbacks
scheduled to be executed after the call to C<redirect> will continue to be
executed. In that case, C<< $cbh->abort >> will not be called; rather,
MasonX::ApacheHandler::WithCallbacks will finish executing all remaining
callbacks and then check the status and abort before Mason creates and
executes a component stack. If the C<$wait> argument is unspecified or false,
then the request will be immediately terminated without executing subsequent
callbacks or, of course, any Mason components. This approach relies on the
execution of C<< $cbh->abort >>.

Since C<< $cbh->redirect >> calls C<< $cbh->abort >>, it will be trapped by an
C<eval {}> block. If you are using an C<eval {}> block in your code to trap
exceptions, you need to make sure to rethrow these exceptions, like this:

  eval {
      ...
  };

  die $@ if $cbh->aborted;

  # handle other exceptions

=head3 abort

  $cbh->abort($status);

Aborts the current request without executing any more callbacks or any Mason
components. The C<$status> argument specifies the HTTP request status code to
be returned to Apache.

C<abort()> is implemented by throwing an HTML::Mason::Exception::Abort object
and can thus be caught by C<eval{}>. The C<aborted> method is a shortcut for
determining whether an exception was generated by C<abort()>.

=head3 aborted

  die $err if $cbh->aborted;
  die $err if $cbh->aborted($err);

Returns true or C<undef> to indicate whether the specified C<$err> was
generated by C<abort()>. If no C<$err> argument is passed, C<aborted()>
examines C<$@>, instead.

In this code, we catch and process fatal errors while letting C<abort()>
exceptions pass through:

  eval { code_that_may_die_or_abort() };
  if (my $err = $@) {
      die $err if $cbh->aborted($err);

      # handle fatal errors...
  }

C<$@> can lose its value quickly, so if you're planning to call
C<< $cbh->aborted >> more than a few lines after the C<eval>, you should save
C<$@> to a temporary variable and explicitly pass it to C<aborted()> as in the
above example.

=head1 SUBCLASSING

Under Perl 5.6.0 and later, MasonX::CallbackHandler offers an object-oriented
callback interface. The object-oriented approach is to subclass
MasonX::CallbackHandler, add the callback methods you need, and specify a
class key that uniquely identifies your subclass across all
MasonX::CallbackHandler subclasses in your application. The key is to use Perl
method attributes to identify methods as callback methods, so that
MasonX::CallbackHandler can find them and execute them when the time
comes. Here's an example:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  use strict;

  __PACKAGE__->register_subclass( class_key => 'MyHandler' );

  sub build_utc_date : Callback( priority => 2 ) {
      my $self = shift;
      my $args = $self->request_args;
      $args->{date} = sprintf "%04d-%02d-%02dT%02d:%02d:%02d",
        delete @{$args}{qw(year month day hour minute second)};
  }

This argument-triggered callback can then be executed via an HTML form field
such as this:

  <input type="submit" name="MyHandler|build_utc_date_cb" value="Build Date" />

Think of the part of the name preceding the pipe (the package key) as the
class name, and the part of the name after the pipe (the callback key) as the
method to call (plus '_cb'). If multiple arguments (form fields) use the
"MyHandler" class key in a single request, then a single
MyApp::CallbackHandler object instance will be used to execute each of those
callback methods for that request.

To configure your MasonX::ApacheHandler::WithCallbacks object to use this
callback, use its C<cb_classes> constructor parameter:

  my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( cb_classes => [qw(MyHandler)] );
  $ah->handle_request($r);

Now, there are a few of things to note in the above callback class example.
The first is the call to C<< __PACKAGE__->register_subclass >>. This step is
required in all callback subclasses in order that MasonX::CallbackHandler will
know about them, an thus they can be loaded into an instance of a
MasonX::ApacheHandler::WithCallbacks object via its C<cb_classes> constructor
parameter.

Second, a callback class key B<must> be declared for the class. This can be
done either by implementing the C<CLASS_KEY()> class method in your subclass, or
by passing the C<class_key> parameter to C<< __PACKAGE__->register_subclass >>,
which will then create the C<CLASS_KEY()> method for you. If no callback key
is declared, then MasonX::CallbackHandler will throw an exception when you try
to load your subclass' callback methods into a
MasonX::ApacheHandler::WithCallbacks object.

One other, optional parameter, C<default_priority>, may also be passed to
C<register_subclass()>. The value of this parameter (an integer between 0 and
9) will be used to create a C<DEFAULT_PRIORITY()> class method in the
subclass. You can also explicitly implement the C<DEFAULT_PRIORITY()> class
method in the subclass, if you'd rather. All argument-triggered callback
methods in that class will have their priorities set to the value returned by
C<DEFAULT_PRIORITY()>, unless they override it via their C<Callback>
attributes.

And finally, notice the C<Callback> attribute on the C<build_utc_date> method
declaration. This attribute is what identifies C<build_utc_date> as an
argument-triggered callback. Without the C<Callback> attribute, any subroutine
declaration in your subclass will just be a subroutine or a method, but it
won't be a callback, and it will never be executed by
MasonX::ApacheHandler::WithCallbacks. One parameter, C<priority>, can be
passed via the C<Callback> attribute. In the above example, we pass
C<< priority => 2 >>, which sets the priority for the callback. Without the
C<priority> parameter, the callback's priority will be set to the value
returned by the C<DEFAULT_PRIORITY()> class method. Of course, the priority
can still be overridden by adding it to the callback trigger key. For example,
here we force the callback priority for the execution of the C<build_utc_date>
callback method for this one field to be the highest priority, "0":

  <input type="submit" name="MyHandler|build_utc_date_cb0" value="Build Date" />

Other parameters to the C<Callback> attribute may be added in future versions
of MasonX::CallbackHandler.

Request callbacks can also be implemented as callback methods using the
C<PreCallback> and C<PostCallback> attributes, which currently support no
parameters.

=head2 Subclassing Examples

At this point, you may be wondering what advantage the object-oriented
callback interface offer over functional callbacks. There are a number of
advantages. First, it allows you to make use of callbacks provided by other
users without having to reinvent the wheel for yourself. Say someone has
implemented the above class with its exceptionally complex C<build_utc_date()>
callback method. You need to have the same functionality, only with fractions
of a second added to the date format so that you can insert them into your
database without an error. (This is admittedly a contrived example, but you
get the idea.) To make it happen, you merely have to subclass the above class
and override the C<build_utc_date()> method to do what you need:

  package MyApp::CallbackHandler::Subclass;
  use base qw(MyApp::CallbackHandler);
  use strict;

  __PACKAGE__->register_subclass;

  # Implement CLASS_KEY ourselves.
  use constant CLASS_KEY => 'SubHandler';

  sub build_utc_date : Callback( priority => 1 ) {
      my $self = shift;
      $self->SUPER::build_utc_date;
      my $args = $self->request_args;
      $args->{date} .= '.000000';
  }

This callback can then be triggered by an HTML field such as this:

  <input type="submit" name="SubHandler|build_utc_date_cb" value="Build Date" />

Note that we've used the "SubHandler" class key. If we used the "MyHandler"
class key, then the C<build_utc_date()> method would be called on an instance
of the MyApp::CallbackHandler class, instead.

=head3 Request Callback Methods

I'll admit that the case for request callback methods is a bit more
tenuous. Granted, a given application may have 100s or even 1000s of request
callbacks, but only one or two request callbacks, if any. But the advantage of
request callback methods is that they encourage code sharing, in that
MasonX::CallbackHandler creates a kind of plug-in architecture for Mason.

For example, say someone has kindly created a MasonX::CallbackHandler
subclass, MasonX::CallbackHandler::Unicodify, with the request callback method
C<unicodify()>, which translates character sets, allowing you to always store
data in the database in Unicode. That's all well and good, as far as it goes,
but let's say that you want to make sure that your Unicode strings are
actually encoded using the Perl C<\x{..}> notation. Again, just subclass:

  package MasonX::CallbackHandler::Unicodify::PerlEncode;
  use base qw(MasonX::CallbackHandler::Unicodify);
  use strict;

  __PACKAGE__->register_subclass( class_key => 'PerlEncode' );

  sub unicodify : PreCallback {
      my $self = shift;
      $self->SUPER::unicodify;
      my $args = $self->request_args;
      encode_unicode($args); # Hand waving.
  }

Now you can just tell MasonX::ApacheHandler::WithCallbacks to use your
subclassed callback handler:

  my $ah = MasonX::ApacheHandler::WithCallbacks->new
  ( cb_classes => [qw(PerlEncode)] );

Yeah, okay, you could just create a second pre-callback request callback to
encode the Unicode characters using the Perl C<\x{..}> notation. But you get
the idea. Better examples welcome.

=head3 Overriding the Constructor

Another advantage to using callback classes is that you can override the
MasonX::CallbackHandler C<new()> constructor. Since every callback for a
single class will be executed on the same instance object in a single request,
you can set up object properties in the constructor that subsequent callback
methods in the same request can then access.

For example, say you had a series of pages that all do different things to
manage objects in your application. Each of those pages might have a number of
fields in common to assist in constructing an object:

  <input type="hidden" name="class" value="MyApp::Spring" />
  <input type="hidden" name="obj_id" value="10" />

Then the remaining HTML on each of these pages has different fields for doing
different things with the object, perhaps with numerous argument-triggered
callbacks. Here's where subclassing comes in handy: you can override the
constructor to construct the object when the callback object is constructed,
so that each of your callback methods doesn't have to:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  use HTML::Mason::MethodMaker( read_write => [qw(object)] );
  use strict;

  __PACKAGE__->register_subclass( class_key => 'MyCBHandler' );

  sub new {
      my $class = shift;
      my $self = $class->SUPER::new(@_);
      my $args = $self->request_args;
      $self->object($args->{class}->lookup( id => $args->{obj_id} ));
  }

  sub save : Callback {
      my $self = shift;
      $self->object->save;
  }

=head1 SUBCLASSING INTERFACE

Much of the interface for subclassing MasonX::CallbackHandler is evident in
the above examples. Here is a reference to the complete callback subclassing
API.

=head2 Callback Class Declaration

Callback classes always subclass MasonX::CallbackHandler, so of course they
must always declare such. In addition, callback classes must always call
C<< __PACKAGE__->register_subclass >> so that MasonX::CallbackHandler is
aware of them and can tell MasonX::ApacheHandler::WithCallbacks about them.

Second, callback classes B<must> have a class key. The class key can be
created either by implementing a C<CLASS_KEY()> class method that returns the
class key, or by passing the C<class_key> parameter to C<register_subclass()>
method. If no C<class_key> parameter is passed to C<register_subclass()> and
no C<CLASS_KEY()> method exists, C<register_subclass()> will create the
C<CLASS_KEY()> class method to return the actual class name. So here are a few
example callback class declarations:

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass( class_key => 'MyCBHandler' );

In this declaration C<register_subclass()> will create a C<CLASS_KEY()> class
method returning "MyCBHandler" in the MyApp::CallbackHandler class.

  package MyApp::AnotherCBHandler;
  use base qw(MyApp::CallbackHandler);
  __PACKAGE__->register_subclass;
  use constant CLASS_KEY => 'AnotherCBHandler';

In this declaration, we've created an explicit C<CLASS_KEY()> class method
(using the handy C<use constant> syntax, so that C<register_subclass()>
doesn't have to.

  package MyApp::FooHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass;

And in this callback class declaration, we've specified neither a C<class_key>
parameter to C<register_subclass()>, nor created a C<CLASS_KEY()> class
method. This causes C<register_subclass()> to create the C<CLASS_KEY()> class
method returning the name of the class itself, i.e., "MyApp::FooHandler".
Thus any argument-triggered callbacks in this class can be triggered by
using the class name in the trigger key:

  <input type="hidden" name="MyApp::FooHandler|take_action_cb" />

A second, optional parameter, C<default_priority>, may also be passed to
C<register_subclass()> in order to set a default priority for all of the
methods in the class (and for all the methods in subclasses that don't declare
their own C<default_priority>s):

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  __PACKAGE__->register_subclass( class_key => 'MyCBHandler',
                                  default_priority => 7 );

As with the C<class_key> parameter, the C<default_priority> parameter creates
a class method, C<DEFAULT_PRIORITY()>. If you'd rather, you can create this
class method yourself; just be sure that its value is a valid priority -- that
is, an integer between "0" and "9":

  package MyApp::CallbackHandler;
  use base qw(MasonX::CallbackHandler);
  use constant DEFAULT_PRIORITY => 7;
  __PACKAGE__->register_subclass( class_key => 'MyCBHandler' );

Any callback class that does not specify a default priority via the
C<default_priority> or by implementing a <DEFAULT_PRIORITY()> class method
will simply inherit the priority returned by
C<< MasonX::CallbackHandler->DEFAULT_PRIORITY >>, which is "5".

B<Note:> It's important that you C<use> any and all MasonX::Callback
subclasses I<before> you C<use MasonX::ApacheHandler::WithCallbacks>. This is
to get around an issue with identifying the names of the callback methods in
mod_perl. Read the comments in the source code if you're interested in
learning more.

=head2 Method Attributes

These method attributes are required to create callback methods in
MasonX::CallbackHandler subclasses.

=head3 Callback

  sub take_action : Callback {
      my $self = shift;
      # Do stuff.
  }

This attribute identifies an argument-triggered callback method. The callback
key is the same as the method name ("take_action" in this example). The
priority for the callback may be set via an optional C<priority> parameter to
the C<Callback> attribute, like so:

  sub take_action : Callback( priority => 5 ) {
      my $self = shift;
      # Do stuff.
  }

Otherwise, the priority will be that returned by C<< $self->DEFAULT_PRIORITY >>.

B<Note:> The priority set via the C<priority> parameter to the C<Callback>
attribute is not inherited by any subclasses that override the callback
method.

=head3 PreCallback

  sub early_action : PreCallback {
      my $self = shift;
      # Do stuff.
  }

This attribute identifies a method as a request callback that gets executed
for every request I<before> any argument-triggered callbacks are executed . No
parameters are currently supported.

=head3 PostCallback

  sub late_action : PostCallback {
      my $self = shift;
      # Do stuff.
  }

This attribute identifies a method as a request callback that gets executed
for every request I<after> any argument-triggered callbacks are executed . No
parameters are currently supported.

=head1 TODO

=over

=item *

Allow methods that override parent methods to inherit the parent method's
priority?

=back

=head1 SEE ALSO

L<MasonX::ApacheHandler::WithCallbacks|MasonX::ApacheHandler::WithCallbacks>
constructs MasonX::CallbackHandler objects and executes the appropriate
callback functions and/or methods. It's worth a read.

=head1 AUTHOR

David Wheeler <david@wheeler.net>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
