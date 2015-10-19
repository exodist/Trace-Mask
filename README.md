# NAME

Trace::Mask - Standard for masking frames in stack traces.

# DESCRIPTION

This is a specification packages can follow to define behaviors stack tracers
may choose to honor. If a module implements this specification that any
compliant stack tracer will render a stack trace that has been modified as
desried by the module. Implementing the spec will have no effect on
non-complient stack tracers. This specification does not effect `caller()` in
any way.

# JUSTIFICATION

There are times where it can be very useful to modify a stack trace.
[Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel) is one example of a module implementing similar behavior. The
problem is that in order to effect a stack trace you either need to use utilies
provided by a specific tracer (such as [Carp](https://metacpan.org/pod/Carp)'s `@CARP_NOT`) or you need to
globally override `caller()` which is awful, and effects things other than
stack traces.

This specification takes a completely different approach. This specification
applies to module that wish to effect stack traces. Only stack traces provided
by compliant tracers will be effected. The benefit here is that modules only
need to use 1 set of tools to potentially effect several tracers. The downside
is that tracers have to opt-in, and may not produce the desired traces.

This specification helps avoid the hackery of overriding `caller()`. An added
benefit is that the specification is unobtrusive, if something is not compliant
it will simply have no effect.

Following this spec also means there is a single universal way to turn it off.
The `$ENV{NO_TRACE_MASK}` environment variable can be used to turn off all
masking ensuring you get a COMPLETE sack trace that has not been modified.

## WHERE IS THIS USEFUL?

Tools like [Test::Exception](https://metacpan.org/pod/Test::Exception) which use [Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel) to hide stack frames so
that the test tool itself is not in the stack trace.

Tools like [Try::Tiny](https://metacpan.org/pod/Try::Tiny) that can benefit from hiding the call to try and the
anonymous codeblock so that stack traces are more sane.

# SPECIFICATION

No module (including this one) is required when implementing the spec. Though
it is a good idea to list the version of the spec you have implemented in the
runtime recommendations for your module.

## %Trace::Mask::MASKS

Packages that wish to mask stack frames may do so by altering the
`%Trace::Mask::MASKS` package variable. Packages may change this variable at
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

No package should ever reset/erase the `%Trace::Mask::MASKS` variable. They
should only ever remove entries they added, even that is not recommended.

You CAN add entries for files+lines that are not under your control. This is an
important allowance as it allows a function to hide the call to itself.

A stack frame is defined based on the return from `caller()` which returns the
`($package, $file, $line)` data of a call in the stack. To manipulate a call
you define the `$MASKS{$file}->{$line}` path in the hash that matches the
call itself.

Inside the `{$file}->{$line}` path you can define the '\*' key which
effects ALL subs called on that file+line.

Sub specific behavior should be defined in `$MASKS{$file}->{$line}` with a
key that contains the sub name as it appears from `caller($l)`.

## CALL MASK HASHES

Numeric keys in the behavior structures are replacement values. If you want to
replace the package listed in the frame then you specify a value for field '0'.
If you want to replace the filename you would put a value for field '1'.
Numeric fields always correspond to the same index in the list returned from
`caller()`.

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

- hide => $BOOL

    This completely hides the frame from a stack trace. This does not modify the
    values of any surrounding frames, the frame is simply dropped from the trace.

- no\_start => $BOOL

    This prevents a stack trace from starting at the given call. This is similar to
    [Carp](https://metacpan.org/pod/Carp)'s `@CARP_NOT` variable. These frames will still appear in the stack
    trace if they are not the start.

- stop => $BOOL

    This tells the stack tracer to stop tracing at this frame. The frame itself
    will be listed in the trace, unless this is combined with the 'hide' option.

- shift => $DELTA,

    This tells the stack tracer to skip `$DELTA` frames after this one,
    effectively upleveling the call. In addition the package+file+line number of
    the bottom-most skipped frame will replace the shifted frames package, file and
    line numbers.

# REFERENCE IMPLEMENTATION

This specification includes a reference implmentation of a stack tracer that
honors the specification. It also provides tools that help produce the
`%MASKS` structure in a maintainable way. These tools make it so that you
do not have to manually update the structure every time line numbers or
filenames change.

## EXPORTS

**Note:** All exports are optional, you must request them if you want them.

- $frames\_ref = trace()
- $frames\_ref = trace($level)

    This produces an array reference containing stack frames of a trace. Each frame
    is an arrayref that matches the return from `caller()`, with the additon that
    the last index contains the arguments used in the call. Never rely on the index
    number of the arguments, always pop them off if you need them, different
    versions of perl may have a different number of values in a stack frame.

    Index 0 of the `$frames_ref` will be the topmost call of the trace, the rest
    will be in descending order.

    See `trace_string()` for a tool to provide a carp-like stack trace.

    `$level` may be specified to start the stack at a deeper level.

- $trace = trace\_string()
- $trace = trace\_string($level)

    This provides a stack trace string similar to `longmess()` from [Carp](https://metacpan.org/pod/Carp).
    Though it does not indent the trace, and it does not take the form of an error
    report.

    `$level` may be specified to start the stack at a deeper level.

- ($pkg, $file, $line) = get\_call()
- ($pkg, $file, $line, $name, ...) = get\_call($level)

    This is a `caller()` emulator that honors the stack tracing specifications.
    Please do not override `caller()` with this. This implementation take a FULL
    stack trace on each call, and returns just the desired frame from that trace.

- hide\_this\_call()
- hide\_this\_call($level)

    Hide the call to the current function. Optionally you can specify `$level` to
    hide a call to a deeper sub, useful for wrappers. Keep in mind this
    adds/modifies entries for the file and line where the current executing sub was
    called, with may be a file/line outside of your own codebase.

- stop\_at\_this\_call()
- stop\_at\_this\_call($level)

    Make stack traces stop at the call to the currently running sub. That means
    only this frame, and frames it calls will be shown in the trace. You can also
    use `hide_this_frame()` to make a trace only show nested frames.

    **Note:** This must be called before calling any other subs for it to have any
    effect.

- no\_start\_at\_this\_call()
- no\_start\_at\_this\_call($level)

    Make sure stack traces do not start at the call to the currently running sub.

- shift\_this\_call($delta)
- shift\_this\_call($delta, $level)

    Raise the level of the current sub in the stack trace. This effectively hides
    the frame before this one, but this one inherits the package, file, and line of
    the previous frame. This has the same effect on the trace as the `goto &sub`
    form of goto. `$delta` is how many levels the frame should be raised.
    `$level` can be used to raise a deeper frame than the current one.

- hide\_call()
- hide\_call($line\_delta)
- hide\_call($line\_delta, @names)
- $ret = hide\_call(\\&code, @args)

    This function allows you to hide a call from a stack trace. With no arguments
    it will hide any call in the same file+line as the `hide_call()` call itself.
    You can also specify a `$line_delta` meaning it will hide any call in the same
    file+line+line\_delta. These 2 forms are most useful in a BEGIN block.

        sub foo {
            BEGIN { hide_call(1) }; # Hide calls on the next line
            bar(); # This is hidden
        }

        sub foo {
            bar(); BEGIN { hide_call() }; # Hide the call to bar()
        }

    This form is the most performant as `hide_call()` is only called once.

    If `@names` are specified, then the behavior will only be defined for the
    specified sub names. If no names are specified then a '\*' entry is added so
    that it effects all subs on the file+line specified.

    The alternative is to provide a coderef and arguments:

        my $sum = hide_call(sub { $_[0] + $_[1] }, 5, 5);

    This will set the call to be hidden, then it will use `goto &sub` to run your
    code.

    **Note:** In both cases the stack frame is completely dropped from the trace, no
    line numbers or file names will be adjusted in any other frames. The frame is
    simply omitted.

- shift\_call($shift\_delta)
- shift\_call($shift\_delta, $line\_delta)
- shift\_call($shift\_delta, $line\_delta, @names)
- $ret = shift\_call($shift\_delta, \\&code, @args)

    This function will shift a stack frame up by a number of frames, effectively
    hiding the frames between it and its new level. In addition it will adjust the
    file+line numbers listed in the frames. This will produce a stack frame similar
    to one if you had used `goto &sub` in the hidden frames. This is similar to
    the behavior of `uplevel` from [Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel), the differnce is that this one
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

    If `@names` are specified, then the behavior will only be defined for the
    specified sub names. If no names are specified then a '\*' entry is added so
    that it effects all subs on the file+line specified.

    As an alternative you can provide a codeblock instead of a line delta:

        my $result = shift_call(1, sub { ... }, ...);

    This is just like `goto &$sub` as far as stack traces are concerned. However
    `caller()` is not effected, and you do not actually unwind the current stack
    frame.

    **Note:** This effects ALL calls on the file+line, Putting 2 calls on the same
    line is unlikely to have the desried effect.

- stop\_at\_call()
- stop\_at\_call($line\_delta)
- stop\_at\_call($line\_delta, @names)
- $ret = stop\_at\_call(\\&code, @args)

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

    If `@names` are specified, then the behavior will only be defined for the
    specified sub names. If no names are specified then a '\*' entry is added so
    that it effects all subs on the file+line specified.

    Alternatively you can use this function to dispatch another sub that is used as
    the bottom:

        my $result = stop_at_call(sub { ... }, ...);

- no\_start\_call()
- no\_start\_call($line\_delta)
- no\_start\_call($line\_delta, @names)
- $ret = no\_start\_call(\\&code, @args)

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

    If `@names` are specified, then the behavior will only be defined for the
    specified sub names. If no names are specified then a '\*' entry is added so
    that it effects all subs on the file+line specified.

    Alternatively you can use this function to dispatch another sub:

        my $result = no_start_call(sub { ... }, ...);

- mask\_call(\\%mask)
- mask\_call(\\%mask, $line\_delta)
- mask\_call(\\%mask, $line\_delta, @names)
- $ret = mask\_call(\\%mask, \\&code, ...)

    This is a higher level version of the other \*\_call functions. Instead of
    defining a single behavior it allows you to define the mask hash itself.

    The primary form is to use this in a BEGIN block near the call:

        sub foo {
            BEGIN { mask_call({...}, 1) }; # Define the mask for the next line
            bar(); # masked
        }

        sub foo {
            bar(); BEGIN { mask_call({...}) }; # Mask this call to bar()
        }

    If `@names` are specified, then the behavior will only be defined for the
    specified sub names. If no names are specified then a '\*' entry is added so
    that it effects all subs on the file+line specified.

    Alternatively you can use this function to dispatch another sub:

        my $result = mask_call({...}, sub { ... }, ...);

- $error = try\_call { ... }

    A reference implementation of `try { ... }` that demonstrates the trace
    masking behavior. Please do not use this in production code, it is a very dumb,
    and not-very-useful implementation of `try` that serves as a demo.

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
    downside however if anything inside the `try` implementation itself is broken.

- $mask = is\_masked(\\@frame)

    If the frame (file+line) have a mask, it will be returned. In cases where the
    file+line have both a '\*' mask and a mask matching the frames sub name, it will
    return a single hashref with a combination of the 2 hashes. Values in the '\*'
    hash will be overriden by the sub-specific one.

        $mask = { %{$wildcard}, %{$sub_specific} };

- $bool = is\_hidden(\\@frame)

    True if the frame should be hidden in a trace.

- $delta = is\_shift(\\@frame)

    The number of levels by which the frame should be shifted.

- $bool = is\_stop(\\@frame)

    True if the frame should be the end of a trace.

- $bool = is\_no\_start(\\@frame)

    True if the frame should not be the start of a trace.

- apply\_mask(\\@frame)

    This modifies the frame provided based on any masks that apply to it. This
    modifies the input argument directly.

- $new = copy\_masked(\\@frame)

    Same as `apply_mask()` except the original is unmodified and a modified copy
    is returned instead.

- $masks\_ref = get\_masks()

    Get a reference to `%Trace::Mask::MASKS`.

# SEE ALSO

[Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel) - Tool for hiding stack frames from all callers, not just stack
traces.

# SOURCE

The source code repository for Test::Stream can be found at
`http://github.com/exodist/Trace-Mask`.

# MAINTAINERS

- Chad Granum &lt;exodist@cpan.org>

# AUTHORS

- Chad Granum &lt;exodist@cpan.org>

# COPYRIGHT

Copyright 2015 Chad Granum &lt;exodist7@gmail.com>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See `http://www.perl.com/perl/misc/Artistic.html`
