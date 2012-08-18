# NAME

Test::LWP::UserAgent - a LWP::UserAgent suitable for simulating and testing network calls

# VERSION

version 0.008

# SYNOPSIS

In your real code:

    use URI;
    use HTTP::Request::Common;
    use LWP::UserAgent;

    my $ua = $self->useragent || LWP::UserAgent->new;

    my $uri = URI->new('http://example.com');
    $uri->port(3000);
    $uri->path('success');
    my $request = POST($uri, a => 1);
    my $response = $ua->request($request);

Then, in your tests:

    use Test::LWP::UserAgent;
    use Test::More;

    Test::LWP::UserAgent->map_response(
        qr{example.com/success}, HTTP::Response->new(200, 'OK', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{example.com/fail}, HTTP::Response->new(500, 'ERROR', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{example.com/conditional},
        sub {
            my $request = shift;
            my $success = $request->uri =~ /success/;
            return HTTP::Response->new(
                ($success ? ( 200, 'OK') : (500, 'ERROR'),
                ['Content-Type' => 'text/plain'], '')
            )
        },
    );

OR, you can use a [PSGI](http://search.cpan.org/perldoc?PSGI) app to handle the requests:

    use HTTP::Message::PSGI;
    Test::LWP::UserAgent->register_psgi('example.com' => sub {
        my $env = shift;
        # logic here...
        [ 200, [ 'Content-Type' => 'text/plain' ], [ 'some body' ] ],
    );

And then:

    # <something which calls the code being tested...>

    my $last_request = Test::LWP::UserAgent->last_http_request_sent;
    is($last_request->uri, 'http://example.com/success:3000', 'URI');
    is($last_request->content, 'a=1', 'POST content');

    # <now test that your code responded to the 200 response properly...>

This feature is useful for testing your PSGI apps (you may or may not find
using [Plack::Test](http://search.cpan.org/perldoc?Plack::Test) easier), or for simulating a server so as to test your
client code.

OR, you can route some or all requests through the network as normal, but
still gain the hooks provided by this class to test what was sent and
received:

    my $useragent = Test::LWP::UserAgent->new(network_fallback => 1);

or:

    $useragent->map_network_response(qr/real.network.host/);

    # ... generate a request...

    # and then in your tests:
    is(
        $useragent->last_useragent->timeout,
        180,
        'timeout was overridden properly',
    );
    is(
        $useragent->last_http_request_sent->uri,
        'uri my code should have constructed',
    );
    is(
        $useragent->last_http_response_received->code,
        200,
        'I should have gotten an OK response',
    );

One common mechanism to swap out the useragent implementation is via a
lazily-built Moose attribute; if no override is provided at construction time,
default to `LWP::UserAgent->new(%options)`.

# METHODS

- `new`

Accepts all options as in [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent), including `use_eval`, an
undocumented boolean which is enabled by default. When set, sending the HTTP
request is wrapped in an `eval {}`, allowing all exceptions to be caught
and an appropriate error response (usually HTTP 500) to be returned. You may
want to unset this if you really want to test extraordinary errors within your
networking code.  Normally, you should leave it alone, as [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) and
this module are capable of handling normal errors.

Plus, this option is added:

    - `network_fallback => <boolean>`

    If true, requests passing through this object that do not match a
    previously-configured mapping or registration will be directed to the network.
    (To only divert _matched_ requests rather than unmatched requests, use
    `map_network_response`, see below.)

    This option is also available as a read/write accessor via
    `$useragent->network_fallback(<value?>)`.

All other methods may be called on a specific object instance, or as a class method.
If called as on a blessed object, the action performed or data returned is
limited to just that object; if called as a class method, the action or data is
global.

- `map_response($request_description, $http_response)`

With this method, you set up what [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) should be returned for each
request received.

The request match specification can be described in multiple ways:

    - string

    The string is matched identically against the `host` field of the [URI](http://search.cpan.org/perldoc?URI) in the request.

    Example:

        $test_ua->map_response('example.com', HTTP::Response->new(500));

    - regexp

    The regexp is matched against the URI in the request.

    Example:

        $test_ua->map_response(qr{foo/bar}, HTTP::Response->new(200));
        $test_ua->map_response(qr{baz/quux}, HTTP::Response->new(500));

    - code

    An arbitrary coderef is passed a single argument, the [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), and
    returns a boolean indicating if there is a match.

        $test_ua->map_response(sub {
                my $request = shift;
                return 1 if $request->method eq 'GET' || $request->method eq 'POST';
            },
            HTTP::Response->new(200),
        );

    - [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) object

    The [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) object is matched identically (including all query
    parameters, headers etc) against the provided object.

The response can be represented either as a literal [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) object, or
as a coderef that is run at the time of matching, with the request passed as
the single argument:

    HTTP::Response->new(...);

or

    sub {
        my $request = shift;
        HTTP::Response->new(...);
    }

Instance mappings take priority over global (class method) mappings - if no
matches are found from mappings added to the instance, the global mappings are
then examined. After no matches have been found, a 404 response is returned.

- `map_network_response($request_description)`

Same as `map_response` above, only requests that match this description will
not use a response that you specify, but instead uses a real [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent)
to dispatch your request to the network.

If called on an instance, all options passed to the constructor (e.g. timeout)
are used for making the real network call. If called as a class method, a
pristine [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) object with no customized options will be used
instead.

- `unmap_all(instance_only?)`

When called as a class method, removes all mappings set up globally (across all
objects). Mappings set up on an individual object will still remain.

When called as an object method, removes _all_ mappings both globally and on
this instance, unless a true value is passed as an argument, in which only
mappings local to the object will be removed. (Any true value will do, so you
can pass a meaningful string.)

- `register_psgi($domain, $app)`

Register a particular [PSGI](http://search.cpan.org/perldoc?PSGI) app (code reference) to be used when requests
for a domain are received (matches are made exactly against
`$request->uri->host`).  The request is passed to the `$app` for processing,
and the [PSGI](http://search.cpan.org/perldoc?PSGI) response is converted back to an [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) (you must
already have loaded [HTTP::Message::PSGI](http://search.cpan.org/perldoc?HTTP::Message::PSGI) or equivalent, as this is not done
for you).

You can also use `register_psgi` with a regular expression as the first
argument, or any of the other forms used by `map_response`, if you wish, as
calling `$test_ua->register_psgi($domain, $app)` is equivalent to:

    $test_ua->map_response(
        $domain,
        sub { HTTP::Response->from_psgi($app->($_[0]->to_psgi)) },
    );

- `unregister_psgi($domain, instance_only?)`

When called as a class method, removes a domain->PSGI app entry that had been
registered globally.  Some mappings set up on an individual object may still
remain.

When called as an object method, removes a domain registration that was made
both globally and locally, unless a true value was passed as the second
argument, in which case only the registration local to the object will be
removed. This allows a different mapping made globally to take over.

If you want to mask a global registration on just one particular instance,
then add `undef` as a mapping on your instance:

    $useragent->map_response($domain, undef);

- `last_http_request_sent`

The last [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) object that this object (if called on an object) or
module (if called as a class method) processed, whether or not it matched a
mapping you set up earlier.

- `last_http_response_received`

The last [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) object that this module returned, as a result of a
mapping you set up earlier with `map_response`. You shouldn't normally need to
use this, as you know what you responded with - you should instead be testing
how your code reacted to receiving this response.

- `last_useragent`

The last Test::LWP::UserAgent object that was used to send a request.
Obviously this only provides new information if called as a class method; you
can use this if you don't have direct control over the useragent itself, to
get the object that was used, to verify options such as the network timeout.

- `network_fallback`

Getter/setter method for the network\_fallback preference that will be used on
this object (if called as an instance method), or globally, if called as a
class method.  Note that the actual behaviour used on an object is the ORed
value of the instance setting and the global setting.

- `send_request($request)`

This is the only method from [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) that has been overridden, which
processes the [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), sends to the network, then creates the
[HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) object from the reply received. Here, we loop through your
local and global domain registrations, and local and global mappings (in this
order) and returns the first match found; otherwise, a simple 404 response is
returned (unless `network_fallback` was specified as a constructor option,
in which case unmatched requests will be delivered to the network.)

All other methods from [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) are available unchanged.

# Use with SOAP requests

To use this module when communicating with a SOAP server (either a real one,
with live network requests, see above ... link here ..., or with one simulated
with mapped responses), simply do this:

    use SOAP::Lite;
    use SOAP::Transport::HTTP;
    $SOAP::Transport::HTTP::Client::USERAGENT_CLASS = 'Test::LWP::UserAgent';

See also ["CHANGING THE DEFAULT USERAGENT CLASS" in SOAP::Transport](http://search.cpan.org/perldoc?SOAP::Transport#CHANGING THE DEFAULT USERAGENT CLASS).

# MOTIVATION

Most mock libraries on the CPAN use [Test::MockObject](http://search.cpan.org/perldoc?Test::MockObject), which is widely considered
not good practice (among other things, `@ISA` is violated, it requires
knowing far too much about the module's internals, and is very clumsy to work
with).

This module is a direct descendant of [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent), exports nothing into
your namespace, and all access is via method calls, so it is fully inheritable
should you desire to add more features or override some bits of functionality.

(Aside from the constructor), it only overrides the one method in [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) that issues calls to the
network, so real [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) and [HTTP::Headers](http://search.cpan.org/perldoc?HTTP::Headers) objects are used
throughout. It provides a method (`last_http_request_sent`) to access the last
[HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), for testing things like the URI and headers that your code
sent to [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent).

# ACKNOWLEDGEMENTS

[AirG Inc.](http://corp.airg.com), my employer, and the first user of this distribution.

mst - Matt S. Trout <mst@shadowcat.co.uk>, for the better name of this
distribution, and for the PSGI registration concept.

Also Yury Zavarin, whose [Test::Mock::LWP::Dispatch](http://search.cpan.org/perldoc?Test::Mock::LWP::Dispatch) inspired me to write this
module, and from where I borrowed some aspects of the API.

# SEE ALSO

[Test::Mock::LWP::Dispatch](http://search.cpan.org/perldoc?Test::Mock::LWP::Dispatch)

[Test::Mock::LWP::UserAgent](http://search.cpan.org/perldoc?Test::Mock::LWP::UserAgent)

[LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent)

[PSGI](http://search.cpan.org/perldoc?PSGI), [HTTP::Message::PSGI](http://search.cpan.org/perldoc?HTTP::Message::PSGI)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
