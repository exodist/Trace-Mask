use Test::Stream -V1, class => 'Trace::Mask';

ref_is($CLASS->masks, \%Trace::Mask::MASKS, "Got the reference");

done_testing;
