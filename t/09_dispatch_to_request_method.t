use strict;
use warnings FATAL => 'all';

use Test::More tests => 6;
use Test::NoWarnings 1.04 ':early';
use Test::Deep 0.110;
use Test::Warn;

use HTTP::Request::Common;
use HTTP::Response;
use Test::LWP::UserAgent;

{
    package MyDispatcher;
    use strict;
    use warnings;

    sub new
    {
        my $class = shift;
        return bless {}, $class;
    }
    sub request
    {
        my ($self, $request) = @_;
        HTTP::Response->new(200, undef, [], 'response from ' . $request->uri);
    }
}


my $useragent = Test::LWP::UserAgent->new;

$useragent->map_response('foo.com', 'MyDispatcher');
$useragent->map_response('bar.com', MyDispatcher->new);

warning_is
    { $useragent->map_response('null.com', 'Foo') }
    "map_response: response is not a coderef or an HTTP::Response, it's a non-object",
    'appropriate warning when creating a bad mapping',
;

cmp_deeply(
    $useragent->request(GET('http://foo.com')),
    all(
        isa('HTTP::Response'),
        methods(
            code => 200,
            content => 'response from http://foo.com',
        ),
    ),
    'can dispatch to a class that implements request()',
);

cmp_deeply(
    $useragent->request(GET('http://bar.com')),
    all(
        isa('HTTP::Response'),
        methods(
            code => 200,
            content => 'response from http://bar.com',
        ),
    ),
    'can dispatch to an instance that implements request()',
);

warning_is
    {
        cmp_deeply(
            $useragent->request(GET('http://null.com')),
            all(
                isa('HTTP::Response'),
                methods(
                    code => 500,
                ),
            ),
            'cannot dispatch to a bare string',
        );
    }
    "response from coderef is not a HTTP::Response, it's a non-object",
    'appropriate warning when attempting to dispatch inappropriately',
;

