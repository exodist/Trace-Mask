package Trace::Mask;
use strict;
use warnings;

use Scalar::Util qw/reftype looks_like_number refaddr blessed/;
use B;

our $VERSION = "0.000001";

use Exporter qw/import/;
our @EXPORT_OK = qw{
    hide_call shift_call mask_call stop_at_call no_start_call try_call
    hide_this_call shift_this_call stop_at_this_call no_start_at_this_call
    is_masked is_hidden is_shift is_stop is_no_start
    apply_mask copy_masked
    get_masks
    get_call
    trace trace_string
};

sub get_masks() { no warnings 'once'; \%Trace::Mask::MASKS }

sub subname {
    my $cobj = B::svref_2object($_[0]);
    my $package = $cobj->GV->STASH->NAME;
    my $subname = $cobj->GV->NAME;
    return "$package\::$subname";
}

sub hide_call {
    my $arg = shift;
    my ($pkg, $file, $line) = caller(0);
    my $masks = get_masks();

    unless (ref $arg) {
        $arg ||= 0;
        if (@_) {
            $masks->{$file}->{$line + $arg}->{$_}->{hide} = 1 for @_;
        }
        else {
            $masks->{$file}->{$line + $arg}->{'*'}->{hide} = 1;
        }
        return;
    }

    die "Invalid argument to hide_call(): $arg at $file line $line.\n"
        unless reftype($arg) eq 'CODE';

    my $name = subname($arg);
    $masks->{$file}->{$line}->{$name}->{hide} = 1;

    @_ = (@_);    # Hide the shifted args
    goto &$arg;
}

sub stop_at_call {
    my $arg = shift;
    my ($pkg, $file, $line) = caller(0);
    my $masks = get_masks();

    unless (ref $arg) {
        $arg ||= 0;
        if (@_) {
            $masks->{$file}->{$line + $arg}->{$_}->{stop} = 1 for @_;
        }
        else {
            $masks->{$file}->{$line + $arg}->{'*'}->{stop} = 1;
        }
        return;
    }

    die "Invalid argument to stop_at_call(): $arg at $file line $line.\n"
        unless reftype($arg) eq 'CODE';

    my $name = subname($arg);
    $masks->{$file}->{$line}->{$name}->{stop} = 1;

    @_ = (@_);    # Hide the shifted args
    goto &$arg;
}

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

sub hide_this_call {
    my ($level) = @_;
    $level ||= 0;
    $level += 1;
    my @caller = caller($level);
    my $masks  = get_masks();
    $masks->{$caller[1]}->{$caller[2]}->{$caller[3]}->{hide} = 1;
}

sub shift_this_call {
    my ($delta, $level) = @_;
    $level ||= 0;
    $level += 1;
    my @caller = caller($level);
    my $masks = get_masks();
    $masks->{$caller[1]}->{$caller[2]}->{$caller[3]}->{shift} = $delta;
}

sub stop_at_this_call {
    my ($level) = @_;
    $level ||= 0;
    $level += 1;
    my @caller = caller($level);
    my $masks  = get_masks();
    $masks->{$caller[1]}->{$caller[2]}->{$caller[3]}->{stop} = 1;
}

sub no_start_at_this_call {
    my ($level) = @_;
    $level ||= 0;
    $level += 1;
    my @caller = caller($level);
    my $masks  = get_masks();
    $masks->{$caller[1]}->{$caller[2]}->{$caller[3]}->{no_start} = 1;
}

sub try_call(&) {
    my $code = shift;

    # Hide the call to try_call
    hide_this_call();

    local $@;
    BEGIN { hide_call(1) } # Hides both the eval, and the anon-block call
    my $ok = eval { $code->(); 1 };
    return if $ok;
    return $@ || "error was masked!";
}

sub is_masked {
    my ($call) = @_;
    my ($pkg, $file, $line, $sub) = @$call;
    my $masks = get_masks();

    # Nope
    return undef unless exists $masks->{$file};
    return undef unless exists $masks->{$file}->{$line};

    # Lets see if any apply to us
    my $all = $masks->{$file}->{$line}->{'*'};
    my $us  = $sub ? $masks->{$file}->{$line}->{$sub} : undef;

    return {%$all, %$us} if $us && $all;
    return {%$all} if $all;
    return {%$us}  if $us;

    # Nothing
    return undef;
}

sub is_hidden {
    my ($call) = @_;
    my $mask = is_masked($call) || return 0;
    return $mask->{hide} || 0;
}

sub is_shift {
    my ($call) = @_;
    my $mask = is_masked($call) || return 0;
    return $mask->{shift} || 0;
}

sub is_stop {
    my ($call) = @_;
    my $mask = is_masked($call) || return 0;
    return $mask->{stop} || 0;
}

sub is_no_start {
    my ($call) = @_;
    my $mask = is_masked($call) || return 0;
    return $mask->{no_start} || 0;
}

sub apply_mask {
    my ($call) = @_;
    my $mask = is_masked($call);
    return unless $mask;

    my $args = pop @$call if @$call && ref($call->[-1]) && reftype($call->[-1]) eq 'ARRAY';

    for my $idx (grep { m/^\d+$/ } keys %$mask) {
        next unless exists $mask->{$idx};
        $call->[$idx] = $mask->{$idx};
    }

    push @$call => $args if $args;

    return $call;
}

sub copy_masked {
    my ($call) = @_;
    my $copy = [@$call];
    apply_mask($copy);
    return $copy;
}

sub trace {
    package DB;
    my ($level) = @_;
    $level = 0 unless defined($level);
    $level += 1;

    my @stack;
    STACK: while (my @call = caller($level++)) {
        my $mask = Trace::Mask::is_masked(\@call);

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
                my $pmask = Trace::Mask::is_masked(\@parent);
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

Trace::Mask - Standard for masking frames in stack traces.

=head1 DESCRIPTION

This is a specification packages can follow to define behaviors stack tracers
may choose to honor. If a module implements this specification that any
compliant stack tracer will render a stack trace that has been modified as
desried by the module. Implementing the spec will have no effect on
non-complient stack tracers. This specification does not effect C<caller()> in
any way.

=head1 JUSTIFICATION

There are times where it can be very useful to modify a stack trace.
L<Sub::Uplevel> is one example of a module implementing similar behavior. The
problem is that in order to effect a stack trace you either need to use utilies
provided by a specific tracer (such as L<Carp>'s C<@CARP_NOT>) or you need to
globally override C<caller()> which is awful, and effects things other than
stack traces.

This specification takes a completely different approach. This specification
applies to module that wish to effect stack traces. Only stack traces provided
by compliant tracers will be effected. The benefit here is that modules only
need to use 1 set of tools to potentially effect several tracers. The downside
is that tracers have to opt-in, and may not produce the desired traces.

This specification helps avoid the hackery of overriding C<caller()>. An added
benefit is that the specification is unobtrusive, if something is not compliant
it will simply have no effect.

Following this spec also means there is a single universal way to turn it off.
The C<$ENV{NO_TRACE_MASK}> environment variable can be used to turn off all
masking ensuring you get a COMPLETE sack trace that has not been modified.

=head2 WHERE IS THIS USEFUL?

Tools like L<Test::Exception> which use L<Sub::Uplevel> to hide stack frames so
that the test tool itself is not in the stack trace.

Tools like L<Try::Tiny> that can benefit from hiding the call to try and the
anonymous codeblock so that stack traces are more sane.

=head1 SPECIFICATION

No module (including this one) is required when implementing the spec. Though
it is a good idea to list the version of the spec you have implemented in the
runtime recommendations for your module.

=head2 %Trace::Mask::MASKS

Packages that wish to mask stack frames may do so by altering the
C<%Trace::Mask::MASKS> package variable. Packages may change this variable at
any time, so consumers should not cashe the contents, however they may cache
the reference to the hash itself.

This is an overview of the MASKS structure:

    %Trace::Mask::MASKS = (
        FILE => {
            LINE => {
                '*' => {...},    # Effects all calls on the line

                SUBNAME => {     # effect calls with the specified sub name only
                    # Behaviors
                    hide     => BOOL,     # Hide the frame completely
                    no_start => BOOL,     # Do not start a trace on this frame
                    stop     => BOOL,     # Stop tracing at this frame
                    shift    => DELTA,    # Pretend this frame started X frames before it did

                    # Replacements
                    0 => PACKAGE,         # Replace the package listed in the frame
                    1 => FILE,            # Replace the filename listed in the frame
                    2 => LINE,            # Replace the linenum listed in the frame
                    3 => NAME,            # Replace the subname listen in the frame
                    ...,                  # Replace any index listed in the frame
                }
            }
        }
    );

No package should ever reset/erase the C<%Trace::Mask::MASKS> variable. They
should only ever remove entries they added, even that is not recommended.

You CAN add entries for files+lines that are not under your control. This is an
important allowance as it allows a function to hide the call to itself.

A stack frame is defined based on the return from C<caller()> which returns the
C<($package, $file, $line)> data of a call in the stack. To manipulate a call
you define the C<< $MASKS{$file}->{$line} >> path in the hash that matches the
call itself.

Inside the C<< {$file}->{$line} >> path you can define the '*' key which
effects ALL subs called on that file+line.

Sub specific behavior should be defined in C<< $MASKS{$file}->{$line} >> with a
key that contains the sub name as it appears from C<caller($l)>.

=head2 CALL MASK HASHES

Numeric keys in the behavior structures are replacement values. If you want to
replace the package listed in the frame then you specify a value for field '0'.
If you want to replace the filename you would put a value for field '1'.
Numeric fields always correspond to the same index in the list returned from
C<caller()>.

   {
       # Behaviors
       hide     => BOOL,     # Hide the frame completely
       no_start => BOOL,     # Do not start a trace on this frame
       stop     => BOOL,     # Stop tracing at this frame
       shift    => DELTA,    # Pretend this frame started X frames before it did

       # Replacements
       0 => PACKAGE,         # Replace the package listed in the frame
       1 => FILE,            # Replace the filename listed in the frame
       2 => LINE,            # Replace the linenum listed in the frame
       3 => NAME,            # Replace the subname listen in the frame
       ...,                  # Replace any index listed in the frame
   }

The following additional behaviors may be specified:

=over 4

=item hide => $BOOL

This completely hides the frame from a stack trace. This does not modify the
values of any surrounding frames, the frame is simply dropped from the trace.

=item no_start => $BOOL

This prevents a stack trace from starting at the given call. This is similar to
L<Carp>'s C<@CARP_NOT> variable. These frames will still appear in the stack
trace if they are not the start.

=item stop => $BOOL

This tells the stack tracer to stop tracing at this frame. The frame itself
will be listed in the trace, unless this is combined with the 'hide' option.

=item shift => $DELTA,

This tells the stack tracer to skip C<$DELTA> frames after this one,
effectively upleveling the call. In addition the package+file+line number of
the bottom-most skipped frame will replace the shifted frames package, file and
line numbers.

=back

=head1 REFERENCE IMPLEMENTATION

This specification includes a reference implmentation of a stack tracer that
honors the specification. It also provides tools that help produce the
C<%MASKS> structure in a maintainable way. These tools make it so that you
do not have to manually update the structure every time line numbers or
filenames change.

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

=item hide_this_call()

=item hide_this_call($level)

Hide the call to the current function. Optionally you can specify C<$level> to
hide a call to a deeper sub, useful for wrappers. Keep in mind this
adds/modifies entries for the file and line where the current executing sub was
called, with may be a file/line outside of your own codebase.

=item stop_at_this_call()

=item stop_at_this_call($level)

Make stack traces stop at the call to the currently running sub. That means
only this frame, and frames it calls will be shown in the trace. You can also
use C<hide_this_frame()> to make a trace only show nested frames.

B<Note:> This must be called before calling any other subs for it to have any
effect.

=item no_start_at_this_call()

=item no_start_at_this_call($level)

Make sure stack traces do not start at the call to the currently running sub.

=item shift_this_call($delta)

=item shift_this_call($delta, $level)

Raise the level of the current sub in the stack trace. This effectively hides
the frame before this one, but this one inherits the package, file, and line of
the previous frame. This has the same effect on the trace as the C<goto &sub>
form of goto. C<$delta> is how many levels the frame should be raised.
C<$level> can be used to raise a deeper frame than the current one.

=item hide_call()

=item hide_call($line_delta)

=item hide_call($line_delta, @names)

=item $ret = hide_call(\&code, @args)

This function allows you to hide a call from a stack trace. With no arguments
it will hide any call in the same file+line as the C<hide_call()> call itself.
You can also specify a C<$line_delta> meaning it will hide any call in the same
file+line+line_delta. These 2 forms are most useful in a BEGIN block.

    sub foo {
        BEGIN { hide_call(1) }; # Hide calls on the next line
        bar(); # This is hidden
    }

    sub foo {
        bar(); BEGIN { hide_call() }; # Hide the call to bar()
    }

This form is the most performant as C<hide_call()> is only called once.

If C<@names> are specified, then the behavior will only be defined for the
specified sub names. If no names are specified then a '*' entry is added so
that it effects all subs on the file+line specified.

The alternative is to provide a coderef and arguments:

    my $sum = hide_call(sub { $_[0] + $_[1] }, 5, 5);

This will set the call to be hidden, then it will use C<goto &sub> to run your
code.

B<Note:> In both cases the stack frame is completely dropped from the trace, no
line numbers or file names will be adjusted in any other frames. The frame is
simply omitted.

=item shift_call($shift_delta)

=item shift_call($shift_delta, $line_delta)

=item shift_call($shift_delta, $line_delta, @names)

=item $ret = shift_call($shift_delta, \&code, @args)

This function will shift a stack frame up by a number of frames, effectively
hiding the frames between it and its new level. In addition it will adjust the
file+line numbers listed in the frames. This will produce a stack frame similar
to one if you had used C<goto &sub> in the hidden frames. This is similar to
the behavior of C<uplevel> from L<Sub::Uplevel>, the differnce is that this one
only effects stack traces, it does not effect caller().

The primary form is to provide a shift amount, and optionally a line delta. It
is best to do this in a BEGIN blog so that it only runs once.

    sub foo {
        BEGIN { shift_call(1, 1) }; # shift calls on the next line up a level
        bar(); # This is shifted, the call to foo() will appear to be the call to bar()
    }

    sub foo {
        bar(); BEGIN { shift_call(1) }; # pretend the call to foo() was the call to bar()
    }

If C<@names> are specified, then the behavior will only be defined for the
specified sub names. If no names are specified then a '*' entry is added so
that it effects all subs on the file+line specified.

As an alternative you can provide a codeblock instead of a line delta:

    my $result = shift_call(1, sub { ... }, ...);

This is just like C<goto &$sub> as far as stack traces are concerned. However
C<caller()> is not effected, and you do not actually unwind the current stack
frame.

B<Note:> This effects ALL calls on the file+line, Putting 2 calls on the same
line is unlikely to have the desried effect.

=item stop_at_call()

=item stop_at_call($line_delta)

=item stop_at_call($line_delta, @names)

=item $ret = stop_at_call(\&code, @args)

This function will mark a call as a place where a stack trace should end. By
end this means it is the bottom-most frame that will be reported in the trace.

The primary form is to use this in a BEGIN block near the call:

    sub foo {
        BEGIN { stop_at_call(1) }; # stop tracing at the call on the next line
        bar(); # This call will be the bottom of the trace, the call to foo() will not be seen.
    }

    sub foo {
        bar(); BEGIN { stop_at_call() }; # pretend the call to bar() is the bottom of the stack
    }

If C<@names> are specified, then the behavior will only be defined for the
specified sub names. If no names are specified then a '*' entry is added so
that it effects all subs on the file+line specified.

Alternatively you can use this function to dispatch another sub that is used as
the bottom:

    my $result = stop_at_call(sub { ... }, ...);

=item no_start_call()

=item no_start_call($line_delta)

=item no_start_call($line_delta, @names)

=item $ret = no_start_call(\&code, @args)

This function will prevent the stack from starting at the specified call. The
call will still show up in the trace if it is below the starting frame, but it
will be skipped if it is the top frame.

The primary form is to use this in a BEGIN block near the call:

    sub foo {
        BEGIN { no_start_call(1) }; # The next call is not the top of the trace
        bar(); # This call will not be the top of a stack trace
    }

    sub foo {
        bar(); BEGIN { stop_at_call() }; # If bar() initiates a trace, it is hidden
    }

If C<@names> are specified, then the behavior will only be defined for the
specified sub names. If no names are specified then a '*' entry is added so
that it effects all subs on the file+line specified.

Alternatively you can use this function to dispatch another sub:

    my $result = no_start_call(sub { ... }, ...);

=item mask_call(\%mask)

=item mask_call(\%mask, $line_delta)

=item mask_call(\%mask, $line_delta, @names)

=item $ret = mask_call(\%mask, \&code, ...)

This is a higher level version of the other *_call functions. Instead of
defining a single behavior it allows you to define the mask hash itself.

The primary form is to use this in a BEGIN block near the call:

    sub foo {
        BEGIN { mask_call({...}, 1) }; # Define the mask for the next line
        bar(); # masked
    }

    sub foo {
        bar(); BEGIN { mask_call({...}) }; # Mask this call to bar()
    }

If C<@names> are specified, then the behavior will only be defined for the
specified sub names. If no names are specified then a '*' entry is added so
that it effects all subs on the file+line specified.

Alternatively you can use this function to dispatch another sub:

    my $result = mask_call({...}, sub { ... }, ...);

=item $error = try_call { ... }

A reference implementation of C<try { ... }> that demonstrates the trace
masking behavior. Please do not use this in production code, it is a very dumb,
and not-very-useful implementation of C<try> that serves as a demo.

    use Trace::Mask qw/try_call trace_string/;

    sub foo {
        print trace_string;
    }

    sub bar {
        my $error = try_call { foo() };
        die $error if $error;
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

=item $mask = is_masked(\@frame)

If the frame (file+line) have a mask, it will be returned. In cases where the
file+line have both a '*' mask and a mask matching the frames sub name, it will
return a single hashref with a combination of the 2 hashes. Values in the '*'
hash will be overriden by the sub-specific one.

    $mask = { %{$wildcard}, %{$sub_specific} };

=item $bool = is_hidden(\@frame)

True if the frame should be hidden in a trace.

=item $delta = is_shift(\@frame)

The number of levels by which the frame should be shifted.

=item $bool = is_stop(\@frame)

True if the frame should be the end of a trace.

=item $bool = is_no_start(\@frame)

True if the frame should not be the start of a trace.

=item apply_mask(\@frame)

This modifies the frame provided based on any masks that apply to it. This
modifies the input argument directly.

=item $new = copy_masked(\@frame)

Same as C<apply_mask()> except the original is unmodified and a modified copy
is returned instead.

=item $masks_ref = get_masks()

Get a reference to C<%Trace::Mask::MASKS>.

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
