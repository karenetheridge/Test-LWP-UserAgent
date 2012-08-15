use strict;
use warnings FATAL => 'all';

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        require Test::More;
        Test::More::plan(skip_all => 'these tests use the network, and are for author testing');
    }
}

use Test::More tests => 16;
use Test::NoWarnings 1.04 ':early';
use Test::Deep;

use Test::LWP::UserAgent;
use HTTP::Request::Common;

# I use POST rather than GET everywhere so as to not process the "302
# Redirect" response - there is no need, and the first response is much
# shorter than the second.

{
    my $useragent = Test::LWP::UserAgent->new;
    my $useragent2 = Test::LWP::UserAgent->new;

    ok(!Test::LWP::UserAgent->network_fallback, 'network_fallback not set globally');
    ok(!$useragent->network_fallback, 'network_fallback not set on the instance');

    test_send_request('no mappings', $useragent, POST('http://example.com'), 404);


    $useragent->network_fallback(1);
    ok($useragent->network_fallback, 'network_fallback set on the instance');

    test_send_request('network_fallback on instance', $useragent, POST('http://example.com'), 302);
    test_send_request('network_fallback on other instance', $useragent2, POST('http://example.com'), 404);

    Test::LWP::UserAgent->network_fallback(1);
    ok(Test::LWP::UserAgent->network_fallback, 'network_fallback set globally');
    ok($useragent->network_fallback, 'network_fallback set on the instance');
    ok($useragent->network_fallback, 'network_fallback set on the other instance');

    test_send_request('network_fallback on other instance', $useragent2, POST('http://example.com'), 302);
    test_send_request('network_fallback, with redirect', $useragent2, GET('http://example.com'), 200);

    Test::LWP::UserAgent->network_fallback(0);
    test_send_request('network_fallback clearable', $useragent2, POST('http://example.com'), 404);
}

{
    my $useragent = Test::LWP::UserAgent->new;
    my $useragent2 = Test::LWP::UserAgent->new;

    $useragent->map_network_response('example.com');
    ok(!$useragent->network_fallback, 'network_fallback not set on the instance');
    test_send_request('network response mapped on instance', $useragent, POST('http://example.com'), 302);

    Test::LWP::UserAgent->map_network_response('example.com');
    test_send_request('network response mapped globally', $useragent2, POST('http://example.com'), 302);
}

sub test_send_request
{
    my ($name, $useragent, $request, $expected_code) = @_;

    note "\n$name";

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is($useragent->request($request)->code, $expected_code, $name);
}

