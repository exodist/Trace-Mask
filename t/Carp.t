use Test::Stream -V1, Spec, class => 'Trace::Mask::Carp';
use Trace::Mask::Test qw{
    test_tracer NA
    test_stack_full_combo
};

use Trace::Mask::Util qw/mask_frame/;

use Trace::Mask::Carp qw{
    confess longmess cluck mask parse_carp_line mask_trace
};

imported_ok qw{
    confess longmess cluck mask parse_carp_line mask_trace
};

my $ran = 0;

tests carp_replacements => sub {
    local $ENV{'NO_TRACE_MASK'};

    my @out = test_tracer(
        name    => 'longmess',
        trace   => \&longmess,
        convert => sub {
            my $trace = shift;
            my @stack;

            for my $line (split /[\n\r]+/, $trace) {
                my $info = parse_carp_line($line);
                my $call = [NA, @{$info}{qw/file line/}, $info->{sub} || NA];
                my $args = $info->{args} ? [map { eval $_ } split /\s*,\s*/, $info->{args}] : [];
                push @stack => [$call, $args];
            }

            return \@stack;
        },
    );

    @out = test_tracer(
        name    => 'confess',
        trace   => \&confess,
        convert => sub {
            my $trace = shift;
            my @stack;

            for my $line (split /[\n\r]+/, $trace) {
                my $info = parse_carp_line($line);
                my $call = [NA, @{$info}{qw/file line/}, $info->{sub} || NA];
                my $args = $info->{args} ? [map { eval $_ } split /\s*,\s*/, $info->{args}] : [];
                push @stack => [$call, $args];
            }

            return \@stack;
        },
    );

    @out = test_tracer(
        name    => 'cluck',
        trace   => \&cluck,
        convert => sub {
            my $trace = shift;
            my @stack;

            for my $line (split /[\n\r]+/, $trace) {
                my $info = parse_carp_line($line);
                my $call = [NA, @{$info}{qw/file line/}, $info->{sub} || NA];
                my $args = $info->{args} ? [map { eval $_ } split /\s*,\s*/, $info->{args}] : [];
                push @stack => [$call, $args];
            }

            return \@stack;
        },
    );
};

describe import => sub {
    my $real_confess  = \&Carp::confess;
    my $real_longmess = \&Carp::longmess;
    my $real_cluck    = \&Carp::cluck;

    around_each 'local' => sub {
        # Make sure these handlers get restored
        local $SIG{__WARN__} = $SIG{__WARN__};
        local $SIG{__DIE__}  = $SIG{__DIE__};

        # Make sure carp is restored
        no warnings 'redefine';
        local *Carp::confess  = $real_confess;
        local *Carp::longmess = $real_longmess;
        local *Carp::cluck    = $real_cluck;

        $_[0]->();
    };

    tests global => sub {
        local $SIG{__WARN__};
        local $SIG{__DIE__};

        ok(!$SIG{__WARN__}, "unset __WARN__ handler");
        ok(!$SIG{__DIE__},  "unset __DIE__ handler");

        $CLASS->import('-global');

        ok($SIG{__WARN__}, "set __WARN__ handler");
        ok($SIG{__DIE__},  "set __DIE__ handler");
    };

    tests wrap => sub {
        $CLASS->import('-wrap');
        ref_is(Carp->can('confess'),  $CLASS->can('confess'),  "overrode Carp::confess");
        ref_is(Carp->can('longmess'), $CLASS->can('longmess'), "overrode Carp::longmess");
        ref_is(Carp->can('cluck'),    $CLASS->can('cluck'),    "overrode Carp::cluck");
    };

    tests bad_imports => sub {
        like(
            dies { $CLASS->import('xxx') },
            qr/'xxx' is not exported by $CLASS/,
            "Bad import"
        );

        like(
            dies { $CLASS->import('-xxx', '-yyy') },
            qr/bad flag\(s\): -xxx, -yyy/,
            "Bad flags"
        );
    };
};

tests global_handlers => sub {
    local $SIG{__DIE__};
    local $SIG{__WARN__};
    local $ENV{'NO_TRACE_MASK'};

    $CLASS->import('-global');

    my @out = test_tracer(
        name    => 'confess',
        trace   => \&Carp::confess,
        convert => sub {
            my $trace = shift;
            my @stack;

            for my $line (split /[\n\r]+/, $trace) {
                my $info = parse_carp_line($line);
                my $call = [NA, @{$info}{qw/file line/}, $info->{sub} || NA];
                my $args = $info->{args} ? [map { eval $_ } split /\s*,\s*/, $info->{args}] : [];
                push @stack => [$call, $args];
            }

            return \@stack;
        },
    );

    # Cannot test the global warning handler..
};


done_testing;

__END__


sub _wrap_carp {
    no warnings 'redefine';
    *Carp::confess  = \&confess;
    *Carp::longmess = \&longmess;
    *Carp::cluck    = \&cluck;
}

sub mask(&) {
    my ($code) = @_;

    # We cannot simply intercept the exception at this point, we need to use
    # the sig handler to ensure it gets masked BEFORE it is cought in an any
    # evals.
    local $SIG{__WARN__} = $SIG{__WARN__} || sub { CORE::warn(@_) };
    local $SIG{__DIE__}  = $SIG{__DIE__}  || sub { CORE::die(@_)  };
    _global_override();

    BEGIN { mask_line({hide => 2}, 1) }
    $code->();
}

sub parse_carp_line {
    my ($line) = @_;
    my %out = (orig => $line);

    if ($line =~ m/^(\s*)([^\(]+)\((.*)\) called at (.+) line (\d+)\.?$/) { # Long
        @out{qw/indent sub args file line/} = ($1, $2, $3, $4, $5);
    }
    elsif ($line =~ m/^(\s*)eval \Q{...}\E called at (.+) line (\d+)\.?$/) { # eval
        @out{qw/indent sub file line/} = ('eval', $1, $2, $3);
    }
    elsif ($line =~ m/^(\s*)(.*) at (.+) line (\d+)\.?$/) { # Short
        @out{qw/indent msg file line/} = ($1, $2, $3, $4);
    }

    return \%out if keys %out;
    return undef;
}

sub _do_shift {
    my ($shift, $fields) = @_;

    $fields->{sub}  = $shift->{sub};
    $fields->{args} = $shift->{args};
}

sub _write_carp_line{
    my ($fields) = @_;
    my ($indent, $file, $line, $sub, $msg, $args) = @{$fields}{qw/indent file line sub msg args/};
    $indent ||= "";

    unless ($sub) {
        $msg ||= "";
        return "$indent$msg at $file line $line.\n";
    }

    if ($sub eq 'eval') {
        return "$indent$sub {...} called at $file line $line\n";
    }
    else {
        $args ||= "";
        return "$indent$sub\($args) called at $file line $line\n";
    }
}

sub mask_trace {
    my ($msg, $sub) = @_;
    return $msg if $ENV{NO_TRACE_MASK};
    my @lines = split /[\n\r]+/, $msg;
    return $msg unless @lines > 1;

    my $out = "";
    my ($shift, $last);
    my $skip = 0;

    my $num = 0;
    my $error;
    for my $line (@lines) {
        my $fields = parse_carp_line($line);
        $fields->{sub} ||= $sub unless $num;
        $error = $fields if exists $fields->{msg};
        $num++;

        unless($fields) {
            $out .= "$line\n";
            next;
        }

        my $mask = get_mask(@{$fields}{qw/file line/}, $fields->{sub} || '*');
        $last = $fields unless $mask->{hide} || $mask->{shift};

        $fields->{file} = $mask->{1} if $mask->{1};
        $fields->{line} = $mask->{2} if $mask->{2};
        $fields->{sub}  = $mask->{3} if $mask->{3};

        if ($mask->{shift}) {
            $shift ||= $fields;
            $skip  = $skip ? $skip + $mask->{shift} - 1 : $mask->{shift};
        }
        elsif ($mask->{hide}) {
            $skip  = $skip ? $skip + $mask->{hide} - 1 : $mask->{hide};
        }
        elsif($skip && !(--$skip) && $shift) {
            _do_shift($shift, $fields);
            $shift = undef;
        }

        unless ($skip || ($mask->{no_start} && !$out)) {
            if ($error) {
                $fields->{msg} = $error->{msg};
                $fields->{indent} = $error->{indent};
                delete $fields->{sub};
                $error = undef;
            }
            $out .= _write_carp_line($fields)
        }

        last if $mask->{stop};
    }

    if ($shift) {
        _do_shift($shift, $last);
        $out .= _write_carp_line($last) unless $out && $out =~ m/at \Q$last->{file}\E line $last->{line}/;
    }

    return $out;
}

1;
