use Test2::Bundle::Spec -target => 'Trace::Mask';

ref_is($CLASS->masks, \%Trace::Mask::MASKS, "Got the reference");

done_testing;
