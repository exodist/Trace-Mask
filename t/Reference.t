use Test::Stream -V1, Spec, class => 'Trace::Mask::Reference';
use Trace::Mask;
use Trace::Mask::Util qw/mask_frame/;

use Trace::Mask::Reference qw{
    trace trace_string trace_mask_caller try_example
};

imported_ok qw{
    trace trace_string trace_mask_caller try_example
};

BEGIN {
    *_do_shift     = Trace::Mask::Reference->can('_do_shift')     or die "no _do_shift";
    *render_arg    = Trace::Mask::Reference->can('render_arg')    or die "no render_args";
    *_call_details = Trace::Mask::Reference->can('_call_details') or die "no _call_details";
}

tests render_arg => sub {
    is(render_arg(), "undef", "undef as string");

    is(render_arg(1), 1, "numbers are not quoted");
    is(render_arg(1.5), 1.5, "numbers are not quoted");

    is(render_arg('a'), "'a'", "quote strings");

    like(
        render_arg({}),
        qr/^HASH\(0x.*\)$/,
        "hashref rendered"
    );

    like(
        render_arg(bless({}, 'foo')),
        qr/^foo=HASH\(0x.*\)$/,
        "object rendered"
    );
};

sub do_trace { trace_string(1) }
tests try_example => sub {
    is(try_example { die "xxx\n" }, "xxx\n", "got exception");
    is(try_example { 1 },           undef,   "No exception");

    # Make sure we stop before this frame so it looks like try was called at
    # the root level.
    mask_frame(stop => 1, hide => 1);

    my $trace;
    my $file = __FILE__;
    my $line = __LINE__ + 1;
    my $error = try_example { $trace = do_trace() };
    die $error if $error;

    is($trace, "main::do_trace() called at $file line $line\n", "hid try frames")
        || print STDERR $trace;
};

sub details { _call_details(@_) };
tests _call_details => sub {
    my $line = __LINE__ + 1;
    my @details = details(0,1,2,3);
    is(
        [@{$details[0]}[0,1,2,3]],
        [ __PACKAGE__, __FILE__, $line, 'main::details' ],
        "Got first 4 details from caller"
    );
    is($details[1], [0,1,2,3], "got args for caller");

    @details = details(10000);
    ok(!@details, "no details for bad level");
};

tests _do_shift => sub {
    my $shift = [
        ['a1', 'b1', 1, 'foo1', 'x1', 'y1', 'z1'],
        [qw/a b c/],
        {hide => 1, 1 => 'a', 3 => 'x'},
    ];
    my $frame = [
        ['a2', 'b2', 2, 'foo2', 'x2', 'y2', 'z2'],
        [qw/x y z apple/],
        {hide => 2, 2 => 'b', 3 => 'y'},
    ];
    _do_shift($shift, $frame);

    is(
        $frame,
        [
            ['a2', 'b2', 2, 'foo1', 'x1', 'y1', 'z1'],    # All but first 3 come from shift
            [qw/a b c/],                                  # Directly from shift
            {hide => 2, 1 => 'a', 2 => 'b', 3 => 'x'},    # merged, shift wins, but only for numerics.
        ],
        "Merged shift into frame"
    );
};

describe trace => sub {


};


done_testing;

__END__

sub trace {
    my @stack;

    # Always have to start at 0 since frames can hide frames that come after them.
    my $level = 0;

    # Shortcut
    if ($ENV{NO_TRACE_MASK}) {
        while (my ($call, $args) = _call_details($level++)) {
            push @stack => [$call, $args];
        }
        return @stack;
    }

    my ($shift, $frame);
    my $skip = 0;
    while (my ($call, $args) = _call_details($level++)) {
        my $mask = get_mask(@{$call}[1,2,3]);
        $frame = [$call, $args, $mask];

        if ($mask->{shift}) {
            $shift ||= $frame;
            $skip   += $mask->{shift};
        }
        elsif ($mask->{hide}) {
            $skip += $mask->{hide};
        }
        elsif($skip && !(--$skip) && $shift) {
            _do_shift($shift, $frame);
            $shift = undef;
        }

        # Need to do this even if the frame is not pushed now, it may be pushed
        # later depending on shift.
        for my $idx (keys %$mask) {
            next unless $idx =~ m/^\d+$/;
            next if $idx >= @$call;    # Do not create new call indexes
            $call->[$idx] = $mask->{$idx};
        }

        push @stack => $frame unless $skip || ($mask->{no_start} && !@stack);

        last if $mask->{stop};
    }

    if ($shift) {
        _do_shift($shift, $frame);
        push @stack => $frame unless @stack && $stack[-1] == $frame;
    }

    return \@stack;
}

sub trace_mask_caller {
    my ($level) = @_;
    $level = 0 unless defined($level);

    my $trace = trace();
    return unless $trace && @$trace;

    my $frame = $trace->[$level + 2];
    return unless $frame;

    return @{$frame->[0]}[0, 1, 2] unless @_;
    return @{$frame->[0]};
}

sub trace_string {
    my ($level) = @_;
    $level = 0 unless defined($level);
    $level += 1;
    my $trace = trace();
    shift @$trace while @$trace && $level--;
    my $string = "";
    for my $frame (@$trace) {
        my ($call, $args) = @$frame;
        my $args_str = join ", " => map { render_arg($_) } @$args;
        $args_str ||= '';
        if ($call->[3] eq '(eval)') {
            $string .= "eval { ... } called at $call->[1] line $call->[2]\n";
        }
        else {
            $string .= "$call->[3]($args_str) called at $call->[1] line $call->[2]\n";
        }
    }

    return $string;
}

sub render_arg {
    my $arg = shift;
    return 'undef' unless defined($arg);

    if (ref($arg)) {
        my $type = reftype($arg);

        # Look past overloading
        my $class = blessed($arg) || '';
        my $it = sprintf('0x%x', refaddr($arg));
        my $ref = "$type($it)";

        return $ref unless $class;
        return "$class=$ref";
    }

    return $arg if looks_like_number($arg);
    $arg =~ s/'/\\'/g;
    return "'$arg'";
}


