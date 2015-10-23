package Trace::Mask::Test;
use strict;
use warnings;

use Trace::Mask::Util qw/mask_frame/;

use Exporter qw/import/;
our @EXPORT = qw{
    stack_hide stack_shift stack_stop stack_no_start stack_alter
    stack_shift_and_hide
};

#line 1 "mask_test.pl"
sub stack_hide {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
    hide_1($callback, 'a');
}

sub hide_1 { hide_2($_[0], 'b') }
sub hide_2 { hide_3($_[0], 'c') }
sub hide_3 { mask_frame(hide => 2); hide_4($_[0], 'd') }
sub hide_4 { hide_5($_[0], 'e') }
sub hide_5 { $_[0]->() }

#line 1 "mask_test.pl"
sub stack_shift {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
    shift_1($callback, 'a');
}

sub shift_1 { shift_2($_[0], 'b') }
sub shift_2 { shift_3($_[0], 'c') }
sub shift_3 { mask_frame(shift => 2); shift_4($_[0], 'd') }
sub shift_4 { shift_5($_[0], 'e') }
sub shift_5 { $_[0]->() }

#line 1 "mask_test.pl"
sub stack_stop {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
    stop_1($callback, 'a');
}

sub stop_1 { stop_2($_[0], 'b') }
sub stop_2 { mask_frame(stop => 1); stop_3($_[0], 'c') }
sub stop_3 { stop_3($_[0], 'd') }
sub stop_4 { stop_5($_[0], 'e') }
sub stop_5 { $_[0]->() }

#line 1 "mask_test.pl"
sub stack_no_start {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
    no_start_1($callback, 'a');
}

sub no_start_1 { no_start_2($_[0], 'b') }
sub no_start_2 { no_start_3($_[0], 'c') }
sub no_start_3 { no_start_3($_[0], 'd') }
sub no_start_4 { no_start_5($_[0], 'e') }
sub no_start_5 { $_[0]->() }

#line 1 "mask_test.pl"
sub stack_alter {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
    alter_1($callback, 'a');
}

sub alter_1 { alter_2($_[0], 'b') }
sub alter_2 { alter_3($_[0], 'c') }
sub alter_3 { alter_3($_[0], 'd') }
sub alter_4 { alter_5($_[0], 'e') }
sub alter_5 { $_[0]->() }

#line 1 "mask_test.pl"
sub stack_shift_and_hide {
    my ($callback) = @_;
    mask_frame(stop => 1, hide => 1);
}

1;
