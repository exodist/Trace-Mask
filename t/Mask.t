use strict;
use warnings;
use Test::More tests => 2;

use Trace::Mask;

isa_ok(Trace::Mask->masks, "HASH");

is(Trace::Mask->masks, \%Trace::Mask::MASKS, "Got the reference");
