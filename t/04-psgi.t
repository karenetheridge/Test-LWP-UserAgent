use strict;
use warnings FATAL => 'all';

use Test::Requires 'HTTP::Message::PSGI';
use Test::More tests => 66;
use Test::NoWarnings 1.04 ':early';
use Test::Deep;

use Test::LWP::UserAgent;
use Storable 'freeze';
use HTTP::Request::Common;

my $app_foo = sub {
    my $env = shift;
    return [ 200, ['Content-Type' => 'text/plain' ], [ 'this is the foo app' ]];
};

my $app_bar = sub {
    my $env = shift;
    return [ 200, ['Content-Type' => 'text/html' ], [ 'this is the bar app' ]];
};

my $app_bar2 = sub {
    my $env = shift;
    return [ 200, ['Content-Type' => 'text/plain' ], [ 'this is the alternative bar app' ]];
};

my $app_baz = sub {
    my $env = shift;
    return [ 200, ['Content-Type' => 'image/jpeg' ], [ 'this is the baz app' ]];
};

{
    my $useragent = Test::LWP::UserAgent->new;
    my $useragent2 = Test::LWP::UserAgent->new;

    Test::LWP::UserAgent->register_domain('foo', $app_foo);
    $useragent->register_domain('bar', $app_bar);
    Test::LWP::UserAgent->register_domain('bar', $app_bar2);
    $useragent2->register_domain('baz', $app_baz);
    $useragent->map_response('http://foo', HTTP::Response->new(503));

    test_send_request('foo app (registered globally)', $useragent, GET('http://foo'),
        200, [ 'Content-Type' => 'text/plain' ], 'this is the foo app');

    test_send_request('bar app (registered on the object)', $useragent, GET(URI->new('http://bar')),
        200, [ 'Content-Type' => 'text/html' ], 'this is the bar app');

    test_send_request('baz app (registered on the second object)', $useragent2, GET('http://baz'),
        200, [ 'Content-Type' => 'image/jpeg' ], 'this is the baz app');

    test_send_request('unmatched request', $useragent, GET('http://quux'),
        404, [ ], '');


    $useragent->unregister_domain('bar', 'this_instance_only');

    test_send_request('backup bar app is now available to this instance', $useragent, GET('http://bar'),
        200, [ 'Content-Type' => 'text/plain' ], 'this is the alternative bar app');

    $useragent->unregister_domain('bar');

    test_send_request('bar app (was registered on the instance, but now removed everywhere)',
        $useragent, GET('http://bar'),
        404, [ ], '');


    $useragent->unregister_domain('foo', 'this_instance_only');

    test_send_request('foo app was registered globally, but now removed from the instance only',
        $useragent, GET('http://foo'),
        503, [ ], '');

    test_send_request('foo app (registered globally; still available for other instances)',
        $useragent2, GET('http://foo'),
        200, [ 'Content-Type' => 'text/plain' ], 'this is the foo app');


    $useragent->unregister_all('this_instance_only');

    test_send_request('baz app is not available on this instance', $useragent, GET('http://baz'),
        404, [ ], '');

    test_send_request('baz app is still available on other instances', $useragent2, GET('http://baz'),
        200, [ 'Content-Type' => 'image/jpeg' ], 'this is the baz app');

    $useragent->unregister_all;

    test_send_request('foo removed everywhere; response mapping now visible',
        $useragent, GET('http://foo'),
        503, [ ], '');

    test_send_request('bar app now removed', $useragent, GET('http://baz'),
        404, [ ], '');

    test_send_request('baz app now removed', $useragent, GET('http://baz'),
        404, [ ], '');
}

sub test_send_request
{
    my ($name, $useragent, $request, $expected_code, $expected_headers, $expected_content) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    note "\n", $name;

    my $response = $useragent->request($request);

    # response is what we stored in the useragent
    isa_ok($response, 'HTTP::Response');
    is(
        freeze($useragent->last_http_response_received),
        freeze($response),
        'last_http_response_received',
    );

    cmp_deeply(
        $useragent->last_http_request_sent,
        all(
            isa('HTTP::Request'),
            $request,
        ),
        "$name - request",
    );

    my %header_spec = @$expected_headers;

    cmp_deeply(
        $response,
        methods(
            code => $expected_code,
            ( map { [ header => $_ ] => $header_spec{$_} } keys %header_spec ),
            content => $expected_content,
            request => $useragent->last_http_request_sent,
        ),
        "$name - response",
    );

    ok(
        HTTP::Date::parse_date($response->header('Client-Date')),
        'Client-Date is a timestamp',
    );
}

