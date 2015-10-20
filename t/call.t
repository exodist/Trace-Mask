use strict;
use warnings;
use Test::More 'no_plan';

use Trace::Mask qw{
    hide_call shift_call mask_call stop_at_call no_start_call try_call
    trace trace_string
};

can_ok(__PACKAGE__, qw{
    hide_call shift_call mask_call stop_at_call no_start_call try_call
});

my ($stack, $full);
my ($line1, $line2, $line3);

sub gen_stack {
    $stack = trace;
    local $ENV{NO_TRACE_MASK} = 1;
    $full = trace;
}

sub gen_stack_wrapper {
    gen_stack(@_); $line1 = __LINE__;
}

sub test_a {
    BEGIN { hide_call(1) };
    gen_stack_wrapper(@_); $line3 = __LINE__;
}

test_a(); $line2 = __LINE__;
is($stack->[0]->[0], __PACKAGE__,       "Frame 0 package");
is($stack->[0]->[1], __FILE__,          "Frame 0 package");
is($stack->[0]->[2], $line1,            "Frame 0 line");
is($stack->[0]->[3], 'main::gen_stack', "Frame 0 line");
is($stack->[1]->[0], __PACKAGE__,       "Frame 1 package");
is($stack->[1]->[1], __FILE__,          "Frame 1 package");
is($stack->[1]->[2], $line2,            "Frame 1 line");
is($stack->[1]->[3], 'main::test_a',    "Frame 1 subname");
is_deeply($stack->[0],  $full->[0],  "First frame is the same");
is_deeply($stack->[-1], $full->[-1], "Last frame is the same");
is($full->[1]->[0], __PACKAGE__,               "Hidden Frame package");
is($full->[1]->[1], __FILE__,                  "Hidden Frame package");
is($full->[1]->[2], $line3,                    "Hidden Frame line");
is($full->[1]->[3], 'main::gen_stack_wrapper', "Hidden Frame subname");

sub test_b {
    BEGIN { hide_call(1, 'fake') };
    gen_stack_wrapper(@_); $line3 = __LINE__;
}
test_b(); $line2 = __LINE__;
is_deeply($stack, $full, "hid a different subname, nothing is hidden");
is(@$stack, 3, "3 stack frames");

sub test_c {
    BEGIN { hide_call(1, 'main::gen_stack_wrapper') };
    gen_stack_wrapper(@_); $line3 = __LINE__;
}
test_c(); $line2 = __LINE__;
is_deeply($stack->[0],  $full->[0],  "First frame is the same");
is_deeply($stack->[-1], $full->[-1], "Last frame is the same");
is(@$stack, 2, "2 frames in masked stack");
is(@$full, 3, "3 frames in full stack");

sub test_d {
    hide_call(\&gen_stack_wrapper, 'a'); $line3 = __LINE__;
}
test_d(); $line2 = __LINE__;
is_deeply($stack->[0],  $full->[0],  "First frame is the same");
is_deeply($stack->[-1], $full->[-1], "Last frame is the same");
is(@$stack, 2, "2 frames in masked stack");
is(@$full, 3, "3 frames in full stack");
is_deeply($stack->[0]->[-1], ['a'], "Only the intended arguments show");

eval { hide_call({}) };
like(
    $@,
    qr/Invalid argument to hide_call\(\): HASH/,
    "Got expected error"
);


sub test_e {
    BEGIN { stop_at_call(1) };
    gen_stack_wrapper(); $line3 = __LINE__;
}

test_e(); $line2 = __LINE__;
is_deeply(
    $stack,
    [@{$full}[0,1]],
    "Trace stops before the final frame"
);

sub test_f {
    BEGIN { stop_at_call(1, 'main::gen_stack_wrapper') };
    gen_stack_wrapper(); $line3 = __LINE__;
}

test_f(); $line2 = __LINE__;
is_deeply(
    $stack,
    [@{$full}[0,1]],
    "Trace stops before the final frame"
);

sub test_g {
    BEGIN { stop_at_call(1, 'fake') };
    gen_stack_wrapper(); $line3 = __LINE__;
}

test_g(); $line2 = __LINE__;
is_deeply($stack, $full, "All frames seen");

sub test_h {
    stop_at_call(\&gen_stack_wrapper, 'a'); $line3 = __LINE__;
}

test_h(); $line2 = __LINE__;
is_deeply( $stack->[0]->[-1], ['a'], "Only see desired arg");
is_deeply(
    $stack,
    [@{$full}[0,1]],
    "Trace stops before the final frame"
);

eval { stop_at_call({}) };
like(
    $@,
    qr/Invalid argument to stop_at_call\(\): HASH/,
    "Got expected error"
);



__END__


sub no_start_call {
    my $arg = shift;
    my ($pkg, $file, $line) = caller(0);
    my $masks = get_masks();

    unless (ref $arg) {
        $arg ||= 0;
        if (@_) {
            $masks->{$file}->{$line + $arg}->{$_}->{no_start} = 1 for @_;
        }
        else {
            $masks->{$file}->{$line + $arg}->{'*'}->{no_start} = 1;
        }
        return;
    }

    die "Invalid argument to no_start_call(): '$arg' at $file line $line.\n"
        unless reftype($arg) eq 'CODE';

    my $name = subname($arg);
    $masks->{$file}->{$line}->{$name}->{stop} = 1;

    @_ = (@_);    # Hide the shifted args
    goto &$arg;
}

sub mask_call {
    my $spec = shift;
    my $arg  = shift;

    my ($pkg, $file, $line) = caller(0);

    my $error = validate_spec($spec);
    die "$error at $file line $line.\n" if $error;

    my $masks = get_masks();

    unless (ref $arg) {
        $arg ||= 0;
        if (@_) {
            my $orig = $masks->{$file}->{$line + $arg}->{$_} || {};
            $masks->{$file}->{$line + $arg}->{$_} = {%$orig, %$spec} for @_;
        }
        else {
            my $orig = $masks->{$file}->{$line + $arg}->{$_} || {};
            $masks->{$file}->{$line + $arg}->{'*'} = {%$orig, %$spec};
        }
        return;
    }

    die "Invalid first argument to mask_call(): '$arg' at $file line $line.\n"
        unless reftype($arg) eq 'CODE';

    my $name = subname($arg);
    my $orig = $masks->{$file}->{$line}->{$name} || {};
    $masks->{$file}->{$line}->{$name} = {%$orig, %$spec};

    @_ = (@_);    # Hide the shifted args
    goto &$arg;
}

sub shift_call {
    my $level = shift;
    my $arg   = shift;

    my ($pkg, $file, $line) = caller(0);

    die "Invalid first argument to shift(): '$level' at $file line $line.\n"
        if ref($level) || !looks_like_number($level) || $level < 1;

    my $masks = get_masks();

    unless (ref $arg) {
        $arg ||= 0;
        if (@_) {
            $masks->{$file}->{$line + $arg}->{$_}->{shift} = $level for @_;
        }
        else {
            $masks->{$file}->{$line + $arg}->{'*'}->{shift} = $level;
        }
        return;
    }

    die "Invalid second argument to shift(): '$arg' at $file line $line.\n"
        unless reftype($arg) eq 'CODE';

    my $name = subname($arg);
    $masks->{$file}->{$line}->{$name}->{shift} = $level;

    @_ = (@_);    # Hide the shifted args
    goto &$arg;

}


