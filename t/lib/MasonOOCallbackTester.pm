package MasonOOCallbackTester;

use strict;
use base 'MasonX::CallbackHandler';
use Apache::Constants qw(HTTP_OK);
use strict;

__PACKAGE__->register_subclass( class_key => 'OOTester');

sub simple : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = 'Simple Success';
}

sub complete : Callback(priority => 3) {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = 'Complete Success';
}

sub highest : Callback(priority => 0) {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = 'Priority ' . $self->priority;
}

sub meth_key : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = 'CBKey Success';
}

sub upperit : PreCallback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = uc $args->{result} if $args->{do_upper};
}

sub pre_post : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{chk_post} = 1;
}

sub chk_post : PostCallback {
    my $self = shift;
    my $args = $self->request_args;
    if ($args->{chk_post}) {
        # Most of the methods should return undefined values.
        my @res;
        foreach my $meth (qw(value pkg_key cb_key priority trigger_key)) {
            push @res, $meth => $self->$meth if $self->$meth;
            print STDERR "$meth => '", $self->$meth, "'\n" if $self->$meth;
        }
        if (@res) {
            $args->{result} = "Oops, some of the accessors have values: @res";
        } else {
            $args->{result} = 'Attributes okay';
        }
    }
}

sub lowerit : PostCallback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = lc $args->{result} if $args->{do_lower};
}

sub class : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = __PACKAGE__ . ' => ' . ref $self;
}

sub inherit : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = UNIVERSAL::isa($self, 'MasonX::CallbackHandler') ?
      'Yes' : 'No';
}

sub chk_priority : Callback {
    my $self = shift;
    my $args = $self->request_args;
#    my $val = $self->value;
#    $val = $self->DEFAULT_PRIORITY if $val eq 'def';
    $args->{result} .= " " . $self->priority;
}

sub multi : Callback {
    my $self = shift;
    my $args = $self->request_args;
    my $val = $self->value;
    $args->{result} = scalar @$val;
}

my $url = 'http://example.com/';
sub redir : Callback {
    my $self = shift;
    my $val = $self->value;
    $self->redirect($url, $val);
}

sub set_status_ok : Callback {
    my $self = shift;
    $self->apache_req->status(HTTP_OK);
    $self->abort(HTTP_OK)
}

sub test_redirected : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = $self->redirected eq $url ? 'yes' : 'no';
    $self->abort(HTTP_OK)
}

sub test_aborted : Callback {
    my $self = shift;
    my $args = $self->request_args;
    my $val = $self->value;
    eval { $self->abort(500)} if $val;
    $args->{result} = $self->aborted($@) ? 'yes' : 'no';
    $self->abort(HTTP_OK)
}

sub exception : Callback {
    my $self = shift;
    my $args = $self->request_args;
    if ($self->value) {
        # Throw an exception object.
        HTML::Mason::Exception->throw( error => "He's dead, Jim" );
    } else {
        # Just die.
        die "He's dead, Jim";
    }
}

sub same_object : Callback {
    my $self = shift;
    my $args = $self->request_args;
    if ($self->value) {
        $args->{result} = $args->{obj} eq "$self" ? 'Yes' : 'No';
    } else {
        $args->{obj} = "$self";
    }
}

1;
__END__
