package MasonOOCallbackTesterSub;
use base 'MasonOOCallbackTester';
use strict;

__PACKAGE__->register_subclass(class_key => 'OOTesterSub');

# Try a method with the same name as one in the parent, and which
# calls the super method.
sub inherit : Callback {
    my $self = shift;
    $self->SUPER::inherit;
    my $args = $self->request_args;
    $args->{result} .= ' and ';
    $args->{result} .= UNIVERSAL::isa($self, 'MasonOOCallbackTester') ?
      'Yes' : 'No';
}

# Try a totally new method.
sub subsimple : Callback {
    my $self = shift;
    my $args = $self->request_args;
    $args->{result} = 'Subsimple Success';
}

1;
__END__
