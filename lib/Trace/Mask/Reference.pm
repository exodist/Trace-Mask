package Trace::Mask::Reference;
use strict;
use warnings;

use Carp qw/croak/;

use Scalar::Util qw/reftype looks_like_number refaddr blessed/;

use Trace::Mask::Util qw/mask_frame mask_line/;

use Exporter qw/import/;
our @EXPORT_OK = qw{
    trace
    trace_string
    get_call
    try_example
};

sub try_example(&) {
    my $code = shift;

    # Hide the call to try_example
    mask_frame(hide => 1);

    local $@;
    BEGIN { mask_line({hide => 1}, 1) } # Hides both the eval, and the anon-block call
    my $ok = eval { $code->(); 1 };
    return if $ok;
    return $@ || "error was smashed!";
}

sub trace {
    package DB;
    my ($level) = @_;
    $level = 0 unless defined($level);
    $level += 1;

    my @stack;
    STACK: while (my @call = caller($level++)) {
        my $mask = Trace::Mask::Util::get_mask(@call[1,2,3]);

        # Shortcut if there is no mask, or if masks are disabled
        if ($ENV{NO_TRACE_MASK} || !$mask) {
            push @call  => [@DB::args];
            push @stack => \@call;
            next;
        }

        # Some frames cannot be used as a start
        next if $mask->{no_start} && !@stack;

        # Do not show this frame
        if (my $hide = $mask->{hide}) {
            # Hide, and stop
            last if $mask->{stop};
            next;
        }

        # Get the args now
        my $args = [@DB::args];

        if (my $shift = $mask->{shift}) {
            $level += $shift;
            my $plevel = $level - 1;

            my $warned = 0;
            my @parent;
            while ($plevel) {
                @parent = caller($plevel--);
                next unless @parent;
                my $pmask = Trace::Mask::Util::get_mask(@parent[1,2,3]);
                next       if $pmask->{hide};
                last STACK if $pmask->{stop};
                last       if @parent;
                next       if $warned++;
                warn "invalid shift depth ($shift at $call[1] line $call[2]).\n";
            }

            if (@parent) {
                $call[0] = $parent[0];
                $call[1] = $parent[1];
                $call[2] = $parent[2];
            }
            else {
                warn "could not find a usable level (shifted at $call[1] line $call[2]).\n";
            }
        }

        for my $idx (grep { m/^\d+$/ } keys %$mask) {
            next unless exists $mask->{$idx};
            $call[$idx] = $mask->{$idx};
        }

        push @call  => $args;
        push @stack => \@call;

        # Stop if the frame is a 'stop' frame.
        last if $mask->{stop};
    }

    return \@stack;
}

sub get_call {
    my ($level) = @_;
    $level = 0 unless defined($level);

    my $trace = trace($level + 1);
    return unless $trace && @$trace;

    my $frame = $trace->[$level];
    return unless $frame;

    return @{$frame}[0, 1, 2] unless @_;
    pop @$frame;    # remove args
    return @$frame;
}

sub trace_string {
    my ($level) = @_;
    $level = 0 unless defined($level);
    my $trace  = trace($level + 1);
    my $string = "";
    for my $frame (@$trace) {
        my $args = $frame->[-1];
        my $args_str = join ", " => map { render_arg($_) } @$args;
        $args_str ||= '';
        if ($frame->[3] eq '(eval)') {
            $string .= "eval { ... } called at $frame->[1] line $frame->[2]\n";
        }
        else {
            $string .= "$frame->[3]($args_str) called at $frame->[1] line $frame->[2]\n";
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

1;

__END__

=pod

=head1 NAME

Trace::Mask::Reference - Reference implemtnations of tools and tracers

=head1 DESCRIPTION

This module provides a reference implementation of an L<Stack::Mask> compliant
stack tracer. It also provides reference examples of tools that benefit from
masking stack traces. These tools should B<NOT> be used in production code, but
may be useful in unit tests that verify compliance.

=head1 SYNOPSIS

    use Trace::Mask::Reference qw/try_example trace_string/;

    sub foo {
        print trace_string;
    }

    sub bar {
        my $error = try_example { foo() };
        ...
    }

    sub baz {
        bar();
    }

    baz();

This produces the following stack trace:

    main::foo() called at test.pl line 8
    main::bar() called at test.pl line 13
    main::baz() called at test.pl line 16

Notice that the call to try, the eval it uses inside, and the call to the
anonymous codeblock are all hidden. This effectively removes noise from the
stack trace. It makes 'try' look just like an 'if' or 'while' block. There is a
downside however if anything inside the C<try> implementation itself is broken.

=head2 EXPORTS

B<Note:> All exports are optional, you must request them if you want them.

=over 4

=item $frames_ref = trace()

=item $frames_ref = trace($level)

This produces an array reference containing stack frames of a trace. Each frame
is an arrayref that matches the return from C<caller()>, with the additon that
the last index contains the arguments used in the call. Never rely on the index
number of the arguments, always pop them off if you need them, different
versions of perl may have a different number of values in a stack frame.

Index 0 of the C<$frames_ref> will be the topmost call of the trace, the rest
will be in descending order.

See C<trace_string()> for a tool to provide a carp-like stack trace.

C<$level> may be specified to start the stack at a deeper level.

=item $trace = trace_string()

=item $trace = trace_string($level)

This provides a stack trace string similar to C<longmess()> from L<Carp>.
Though it does not indent the trace, and it does not take the form of an error
report.

C<$level> may be specified to start the stack at a deeper level.

=item ($pkg, $file, $line) = get_call()

=item ($pkg, $file, $line, $name, ...) = get_call($level)

This is a C<caller()> emulator that honors the stack tracing specifications.
Please do not override C<caller()> with this. This implementation take a FULL
stack trace on each call, and returns just the desired frame from that trace.

=item $error = try_example { ... }

A reference implementation of C<try { ... }> that demonstrates the trace
masking behavior. Please do not use this in production code, it is a very dumb,
and not-very-useful implementation of C<try> that serves as a demo.

=back

=head1 SEE ALSO

L<Sub::Uplevel> - Tool for hiding stack frames from all callers, not just stack
traces.

=head1 SOURCE

The source code repository for Trace-Mask can be found at
F<http://github.com/exodist/Trace-Mask>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2015 Chad Granum E<lt>exodist7@gmail.comE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://www.perl.com/perl/misc/Artistic.html>

=cut
