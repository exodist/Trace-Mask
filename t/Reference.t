use Test::Stream -V1, Spec, class => 'Trace::Mask::Reference';
use Trace::Mask;
use Trace::Mask::Util qw/mask_frame/;

use Trace::Mask::Reference qw{
    trace trace_string get_call try_example
};

imported_ok qw{
    trace trace_string get_call try_example
};

BEGIN {
    *render_arg = Trace::Mask::Reference->can('render_arg');
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

sub do_trace { trace_string }

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

done_testing;

__END__


sub _call_details {
    my ($level) = @_;
    $level += 1;

    my @call;
    my @args;
    {
        package DB;
        @call = caller($level);
        @args = @DB::args;
    }

    return unless @call && defined $call[0];
    return (\@call, \@args);
}

sub trace {
    my ($level) = @_;
    $level = 0 unless defined($level);
    $level += 1;

    my @stack;

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

        unless ($skip || ($mask->{no_start} && !@stack)) {
            for my $idx (grep { m/^\d+$/ } keys %$mask) {
                next unless exists $mask->{$idx};
                $call->[$idx] = $mask->{$idx};
            }

            push @stack => $frame;
        }

        last if $mask->{stop};
    }

    _do_shift($shift, $frame) if $shift;

    return \@stack;
}

sub _do_shift {
    my ($shift, $frame) = @_;

    # Args are a direct move
    $frame->[1] = $shift->[1];

    # Merge the masks
    $frame->[2] = { %{$frame->[2]}, %{$shift->[2]} };

    # Copy all caller values from shift except 0-2
    for(my $i = 3; $i < @{$shift->[0]}; $i++) {
        $frame->[0]->[$i] = $shift->[0]->[$i];
    }
}

sub get_call {
    my ($level) = @_;
    $level = 0 unless defined($level);

    my $trace = trace($level + 1);
    return unless $trace && @$trace;

    my $frame = $trace->[$level];
    return unless $frame;

    return @{$frame->[0]}[0, 1, 2] unless @_;
    return @{$frame->[0]};
}

sub trace_string {
    my ($level) = @_;
    $level = 0 unless defined($level);
    my $trace  = trace($level + 1);
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
