package Trace::Mask::Carp;
use strict;
use warnings;

use Carp();
$Carp::Internal{Trace::Mask} = 1;
$Carp::Internal{Trace::Mask::Carp} = 1;
$Carp::Internal{Trace::Mask::Util} = 1;
$Carp::Internal{Trace::Mask::Reference} = 1;
use Trace::Mask::Util qw/get_mask mask_line/;

BEGIN {
    *carp_longmess = Carp->can('longmess') or die "Could not find Carp::longmess";
}

sub longmess {      mask_trace(scalar(carp_longmess(@_)), 'Trace::Mask::Carp::longmess') }
sub confess  { die  mask_trace(scalar(carp_longmess(@_)), 'Trace::Mask::Carp::confess') }
sub cluck    { warn mask_trace(scalar(carp_longmess(@_)), 'Trace::Mask::Carp::cluck') }

sub _my_croak {
    my $msg = shift;
    my @caller = caller(1);
    die "$msg at $caller[1] line $caller[2].\n";
}

sub import {
    my $class = shift;

    my $caller = caller;

    my %flags;

    for my $arg (@_) {
        if ($arg =~ m/^-(.+)$/) {
            $flags{$1} = 1;
        }
        elsif ($arg =~ m/^_/) {
            _my_croak "'$arg' is not exported by $class"
        }
        else {
            my $sub = $class->can($arg) || _my_croak "'$arg' is not exported by $class";
            no strict 'refs';
            *{"$caller\::$arg"} = $sub;
        }
    }

    $class->_global_override if delete $flags{'global'};
    $class->_wrap_carp       if delete $flags{'wrap'};

    my @bad = sort keys %flags;
    return unless @bad;
    _my_croak "bad flag(s): " . join (", ", map { "-$_" } @bad);
}

sub _global_override {
    my $die  = $SIG{__DIE__}  || sub { CORE::die(@_) };
    my $warn = $SIG{__WARN__} || sub { CORE::warn(@_) };

    $SIG{__DIE__} = sub {
        my $error = shift;
        my @caller = caller(1);
        $error = mask_trace($error, $caller[3]) if $caller[3] =~ m/^Carp::(confess|longmess|cluck)$/;
        return $die->($error)
    };

    $SIG{__WARN__} = sub {
        my $msg = shift;
        my @caller = caller(1);
        $msg = mask_trace($msg, $caller[3]) if $caller[3] =~ m/^Carp::(confess|longmess|cluck)$/;
        $warn->($msg);
    };
}

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
