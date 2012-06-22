use strict;
use warnings FATAL => 'all';

use Test::More tests => 12;
use Test::NoWarnings 1.04 ':early';
use Test::Deep;

# simulates real code that we are testing
{
    package MyApp;
    use strict;
    use warnings;

    use URI;
    use HTTP::Request::Common;
    use LWP::UserAgent;

    # in real code, you might want a Moose lazy _build_ua sub for this
    our $useragent = LWP::UserAgent->new;

    sub send_to_url
    {
        my ($self, $method, $base_url, $port, $path, %params) = @_;

        my $uri = URI->new($base_url);
        $uri->port($port);
        $uri->query_form(%params) if keys %params;
        $uri->path($path);

        my $request_sub = HTTP::Request::Common->can($method);
        my $request = $request_sub->($uri);

        my $response = $useragent->request($request);
    }
}

use Test::Mock::LWP::UserAgent::ButAwesome;
my $class = 'Test::Mock::LWP::UserAgent::ButAwesome';

cmp_deeply(
    $class,
    methods(
        last_http_request_sent => undef,
        last_http_response_received => undef,
    ),
    'initial state (class)',
);


cmp_deeply(
    $class->new,
    all(
        isa($class),
        isa('LWP::UserAgent'),
        methods(
            last_http_request_sent => undef,
            last_http_response_received => undef,
        ),
        noclass(superhashof({
            __last_http_request_sent => undef,
            __last_http_response_received => undef,
            __response_map => [],
        })),
    ),
    'initial state (object)',
);

# class methods
{
    $class->map_response(
        'http://foo:3001/success?a=1', HTTP::Response->new(201, 'OK', ['Content-Type' => 'text/plain'], ''));
    $class->map_response(
        qr{foo.+success}, HTTP::Response->new(200, 'OK', ['Content-Type' => 'text/plain'], ''));
    $class->map_response(
        qr{foo.+fail}, HTTP::Response->new(500, 'ERROR', ['Content-Type' => 'text/plain'], ''));

    $MyApp::useragent = $class->new;

    foreach my $test (
        [ 'regexp success', 'POST', 'http://foo', 3000, 'success', { a => 1 },
            str('http://foo:3000/success?a=1'), 200 ],
        [ 'regexp fail', 'POST', 'http://foo', 3000, 'fail', { a => 1 },
            str('http://foo:3000/fail?a=1'), 500 ],
        [ 'string success', 'POST', 'http://foo', 3001, 'success', { a => 1 },
            str('http://foo:3001/success?a=1'), 201 ],

    )
    {
        my ($name, $method, $uri_base, $port, $path, $params, $expected_uri, $expected_code) = @$test;

        my $response = MyApp->send_to_url($method, $uri_base, $port, $path, %$params);

        # response is what we stored in the useragent
        isa_ok($response, 'HTTP::Response');

        cmp_deeply(
            $class->last_http_request_sent,
            all(
                isa('HTTP::Request'),
                methods(
                    uri => $expected_uri,
                ),
            ),
            "$name request",
        );

        cmp_deeply(
            $response,
            methods(
                code => $expected_code,
                [ header => 'Content-Type' ] => 'text/plain',
            ),
            "$name response",
        );

    }

}


