use strict;
use warnings;
use Test::More 'no_plan';

use Trace::Mask::Util qw{
    update_mask
    get_mask
    mask_line
    mask_call
    mask_sub
    mask_frame
};

can_ok(__PACKAGE__, qw{
    update_mask
    get_mask
    mask_line
    mask_call
    mask_sub
    mask_frame
});


__END__

sub update_mask {
    my ($file, $line, $sub, $mask) = @_;

    my $name = ref $sub ? _subname($sub) : $sub;

    my $masks = _MASKS();

    # Get existing ref, if any
    my $ref = $masks->{$file}->{$line}->{$name};

    # No ref, easy!
    return $masks->{$file}->{$line}->{$name} = {%$mask}
        unless $ref;

    # Merge new mask into old
    %$ref = (%$ref, %$mask);

    return;
}

sub mask_line {
    my ($mask, $delta, @subs) = @_;
    my ($pkg, $file, $line) = caller(0);

    push @subs => '*' unless @subs;
    $line += $delta if $delta;

    croak "The first argument to mask_line() must be a hashref"
        unless $mask && ref($mask) && reftype($mask) eq 'HASH';

    croak "The second argument to mask_line() must be an integer"
        if $delta && (ref($delta) || !looks_like_number($delta));

    update_mask($file, $line, $_, {hide => 1}) for @subs;
    return;
}

sub mask_call {
    my $mask = shift;
    my $sub = shift;
    my ($pkg, $file, $line) = caller(0);

    $sub = $pkg->can($sub) unless ref $sub;

    croak "The first argument to mask_call() must be a hashref"
        unless $mask && ref($mask) && reftype($mask) eq 'HASH';

    croak "The second argument to mask_call() must be a coderef, or the name of a sub to call"
        unless $sub && ref($sub) && reftype($sub) eq 'CODE';

    update_mask($file, $line, $sub, $mask);

    @_ = (@_);    # Hide the shifted args
    goto &$sub;
}

sub mask_sub {
    my ($mask, $sub, $file, $line) = @_;
    $file ||= '*';
    $line ||= '*';

    $sub = caller->can($sub) unless ref $sub;

    croak "The first argument to mask_sub() must be a hashref"
        unless $mask && ref($mask) && reftype($mask) eq 'HASH';

    croak "The second argument to mask_sub() must be a coderef, or the name of a sub in the calling package"
        unless $sub && ref($sub) && reftype($sub) eq 'CODE';

    my $name = subname($sub);
    croak "mask_sub() cannot be used on an unamed sub"
        if $name =~ m/__ANON__$/;

    update_mask($file, $line, $name, $mask);
    return;
}

sub mask_frame {
    my %mask = @_;
    my ($pkg, $file, $line, $name) = caller(1);
    update_mask($file, $line, $name, \%mask);
    return;
}

sub get_mask {
    my ($file, $line, $sub) = @_;

    my $name = ref($sub) ? _subname($sub) : $sub;

    my $masks = _MASKS();

    my @order = grep { defined $_ } (
        $masks->{$file}->{'*'}->{'*'},
        $masks->{$file}->{$line}->{'*'},
        $masks->{'*'}->{'*'}->{$name},
        $masks->{$file}->{'*'}->{$name},
        $masks->{$file}->{$line}->{$name},
    );

    return {} unless @order;
    return { map { %{$_} } @order };
}
