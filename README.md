# NAME

Trace::Mask - Standard for masking frames in stack traces.

# DESCRIPTION

This is a specification packages can follow to define behaviors stack tracers
may choose to honor. If a module implements this specification than any
compliant stack tracer will render the stack trace as desired. Implementing the
spec will have no effect on non-complient stack tracers. This specification
does not effect `caller()` in any way.

# PRACTICAL APPLICATIONS

Masking stack traces is not something you want to do every day, but there are
situations where it can be helpful, if not essential.

- Emulate existing language structures

        sub foo {
            if ($cond) { trace() }
        }

    In the example above a stack trace is produced, the call to `foo()` will show
    up, but the `if` block will not. This is useful as the conditional is part of
    the sub, and should not be listed.

    Emulating this behavior would be a useful feature for exception tools that
    provide try/catch/finally or similar control structures.

        try   { ... }
        catch { ... };

    In perl the above would be emulated with 2 subs that take codeblocks in their
    prototype. In a stack trace you see a call to try, and a call to an anonymous
    block. In a stack trace this is distracting at best. Further it is hard to
    distinguish which anonymous block you are in, though tools like [Sub::Name](https://metacpan.org/pod/Sub::Name)
    mitigate this some.

- Testing Tools

    Tools like [Test::Exception](https://metacpan.org/pod/Test::Exception) use [Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel) to achieve a similar effect.
    This is done by globally overriding `caller()`, which can have some
    unfortunate side effects. Using Trace::Mask instead would avoid the nasty side
    effects, would be much faster than overriding `caller()`, and give more
    control over what makes it into the trace.

- One interface to many tools

    Currently [Carp](https://metacpan.org/pod/Carp) provides several configuration variables such as `@CARP_NOT`
    to give you control over where a trace starts. Other modules that provide stack
    traces all provide their own variables. If you want to control stack traces you
    need to account for all the possible tracing tools that could be used. Many
    tracing tools do not provide enough control, including `Carp` itself.

# SPECIFICATION

No module (including this one) is required when implementing the spec. Though
it is a good idea to list the version of the spec you have implemented in the
runtime recommendations for your module. There are no undesired side effects as
the specification is completely opt-in, both for modules that want to effect
stack traces, and for the stack tracers themselves.

## %Trace::Mask::MASKS

Packages that wish to mask stack frames may do so by altering the
`%Trace::Mask::MASKS` package variable. Packages may change this variable at
any time, so consumers should not cache the contents, however they may cache
the reference to the hash itself.

This is an overview of the MASKS structure:

    %Trace::Mask::MASKS = (
        FILE => {
            LINE => {
                SUBNAME => {
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
`($package, $file, $line, $subname)` data of a call in the stack. To
manipulate a call you define the `$MASKS{$file}->{$line}->{$subname}` path
in the hash that matches the call itself.

'FILE', 'LINE', and 'SUBNAME' can all be replaced with the wildcard `'*'`
string to apply to all:

    # Effect all calls to Foo::foo in any file
    ('*' => { '*' => { Foo::foo => { ... }}})

    # Effect all sub calls in Foo.pm
    ('Foo.pm' => { '*' => { '*' => { ... }}});

You cannot use 3 wildcards to effect all subs. The 3 wildcard entry will be
ignored by a compliant tracer.

    # This is not allowed, the entry will be ignored
    ('*' => { '*' => { '*' => { ... }}});

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
    line numbers. The `$DELTA` value must be a positive integer greater than 0.

## MASK RESOLUTION

Multiple masks in the `%Trace::Mask::MASKS` structure may apply to any given
stack frame, a compliant tracer will account for all of them. A simple hash
merge is sufficient so long as they are merged in the correct order. Here is an
example:

    my $masks_ref = \%Trace::Mask::MASKS;

    my @all = grep { defined $_ } (
        $masks_ref->{$file}->{'*'}->{'*'},
        $masks_ref->{$file}->{$line}->{'*'},
        $masks_ref->{'*'}->{'*'}->{$name},
        $masks_ref->{$file}->{'*'}->{$name},
        $masks_ref->{$file}->{$line}->{$name},
    );

    my %final = map { %{$_} } @all;

The most specific path should win out (override others). Rightmost path
component is considered the most important. More wildcards means less specific.
Paths may never have wildcards for all 3 components.

## $ENV{'NO\_TRACE\_MASK'}

If this environment variable is set to true then all masking rules should be
ignored, tracers should produce full and complete stack traces.

# CLASS METHODS

The `masks()` method is defined in [Trace::Mask](https://metacpan.org/pod/Trace::Mask), it returns a reference to
the `%Trace::Mask::MASKS` hash for easy access. It is fine to cache this
reference, but not the data it contains.

# REFERENCE

[Trace::Mask::Reference](https://metacpan.org/pod/Trace::Mask::Reference) is included in this distribution. The Reference
module contains example tracers, and example tools that benefit from masking
stack traces. The examples in this module should NOT be used in production
code.

# UTILS

[Trace::Mask::Util](https://metacpan.org/pod/Trace::Mask::Util) is included in this distribution. The util module provides
utilities for adding stack trace masking behavior. The utilities provided by
this module are considered usable in production code.

# SEE ALSO

[Sub::Uplevel](https://metacpan.org/pod/Sub::Uplevel) - Tool for hiding stack frames from all callers, not just stack
traces.

# SOURCE

The source code repository for Trace-Mask can be found at
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
