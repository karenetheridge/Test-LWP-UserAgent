use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';

use HTTP::Message::PSGI ();
use HTTP::Response ();
use Test::LWP::UserAgent ();

{
    my $ua = Test::LWP::UserAgent->new->register_psgi( abc => sub {} );
    isa_ok $ua, 'Test::LWP::UserAgent', 'register_psgi';
}

{
    my $ua = Test::LWP::UserAgent->new->map_response(
        abc => HTTP::Response->new(200),
    );
    isa_ok $ua, 'Test::LWP::UserAgent', 'map_response';
}

{
    my $ua = Test::LWP::UserAgent->new->register_psgi( abc => sub {} )
        ->unregister_psgi('abc');
    isa_ok $ua, 'Test::LWP::UserAgent', 'unregister_psgi';
}

done_testing();
