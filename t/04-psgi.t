use strict;
use warnings FATAL => 'all';

use Test::More tests => 5;
use Test::NoWarnings 1.04 ':early';

use Test::LWP::UserAgent;

my $app_foo = sub {
    my $env = shift;

    # extract params from the request

    return 200, ['Content-Type' => 'text/plain' ], [ 'this is the foo app' ];
};

my $app_bar = sub {
    my $env = shift;

    return 200, ['Content-Type' => 'text/plain' ], [ 'this is the bar app' ];
};

{
    my $useragent = Test::LWP::UserAgent->new;

    $useragent->register_domain('foo', $app_foo);
    $useragent->register_domain('bar', $app_foo);

    # XXX add some params to the $uri
    my $response = $useragent->get('http://foo');

    isa_ok($response, 'HTTP::Response');
    cmp_deeply(
        $response,
        methods(
            code => 200,
            headers => 'content-type...',
            content => 'this is the foo app',
        ),
    );
}


