package MasonOOCallbackTesterReqSub;
use base 'MasonOOCallbackTester';
use strict;

__PACKAGE__->register_subclass(class_key => 'ReqSub');

# Try the methods with the sames name as those in the parent, and which
# call their super methods.
sub upperit : PreCallback {
    my $self = shift;
    $self->SUPER::upperit;
    my $args = $self->request_args;
    $args->{result} .= ' Overridden' if $args->{do_upper};
}

sub lowerit : PostCallback {
    my $self = shift;
    $self->SUPER::lowerit;
    my $args = $self->request_args;
    $args->{result} .= ' Overridden' if $args->{do_lower};
}

# Try totally new methods.
sub sub_pre : PreCallback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} .= ' PreCallback'
      if $args->{do_lower} or $args->{do_upper};
}

sub sub_post : PostCallback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} .= ' PostCallback'
      if $args->{do_lower} or $args->{do_upper};
}

1;
__END__
