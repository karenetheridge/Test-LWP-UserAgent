# NAME

Test::LWP::UserAgent - A LWP::UserAgent suitable for simulating and testing network calls

# VERSION

version 0.024

# SYNOPSIS

In your application code:

    use URI;
    use HTTP::Request::Common;
    use LWP::UserAgent;

    my $useragent = $self->useragent || LWP::UserAgent->new;

    my $uri = URI->new('http://example.com');
    $uri->port('3000');
    $uri->path('success');
    my $request = POST($uri, a => 1);
    my $response = $useragent->request($request);

Then, in your tests:

    use Test::LWP::UserAgent;
    use Test::More;

    my $useragent = Test::LWP::UserAgent->new;
    $useragent->map_response(
        qr{example.com/success}, HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));
    $useragent->map_response(
        qr{example.com/fail}, HTTP::Response->new('500', 'ERROR', ['Content-Type' => 'text/plain'], ''));

    # now, do something that sends a request, and test how your application
    # responds to that response

# DESCRIPTION

This module is a subclass of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) which overrides a few key
low-level methods that are concerned with actually sending your request over
the network, allowing an interception of that request and simulating a
particular response.  This greatly facilitates testing of client networking
code where the server follows a known protocol.

The synopsis describes a classic case where you want to test how your
application reacts to various responses from the server.  This module will let
you send back various responses depending on the request, without having to
set up a real server to test against.  This can be invaluable when you need to
test edge cases or error conditions that are not normally returned from the
server.

There are a lot of different ways you can set up the response mappings, and
hook into this module; see the documentation for the individual interface
methods.

You can use a [PSGI](https://metacpan.org/pod/PSGI) app to handle the requests - see `examples/call_psgi.t`
in this dist, and also ["register\_psgi"](#register_psgi) below.

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
        '200',
        'I should have gotten an OK response',
    );

## Ensuring the right useragent is used

Note that [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) itself is not monkey-patched - you must use
this module (or a subclass) to send your request, or it cannot be caught and
processed.

One common mechanism to swap out the useragent implementation is via a
lazily-built Moose attribute; if no override is provided at construction time,
default to `LWP::UserAgent->new(%options)`.

Additionally, most methods can be called as class methods, which will store
the settings globally, so that any instance of [Test::LWP::UserAgent](https://metacpan.org/pod/Test::LWP::UserAgent) can use
them, which can simplify some of your application code.

# METHODS

## `new`

Accepts all options as in [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent), including `use_eval`, an
undocumented boolean which is enabled by default. When set, sending the HTTP
request is wrapped in an `eval {}`, allowing all exceptions to be caught
and an appropriate error response (usually HTTP 500) to be returned. You may
want to unset this if you really want to test extraordinary errors within your
networking code.  Normally, you should leave it alone, as [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) and
this module are capable of handling normal errors.

Plus, this option is added:

- `network_fallback => <boolean>`

    If true, requests passing through this object that do not match a
    previously-configured mapping or registration will be directed to the network.
    (To only divert _matched_ requests rather than unmatched requests, use
    `map_network_response`, see below.)

    This option is also available as a read/write accessor via
    `$useragent->network_fallback(<value?>)`.

**All other methods below may be called on a specific object instance, or as a class method.**
If called as on a blessed object, the action performed or data returned is
limited to just that object; if called as a class method, the action or data is
global.

## `map_response($request_specification, $http_response)`

With this method, you set up what [HTTP::Response](https://metacpan.org/pod/HTTP::Response) should be returned for each
request received.

The request match specification can be described in multiple ways:

- string

    The string is matched identically against the `host` field of the [URI](https://metacpan.org/pod/URI) in the request.

        $test_ua->map_response('example.com', HTTP::Response->new('500'));

- regexp

    The regexp is matched against the URI in the request.

        $test_ua->map_response(qr{foo/bar}, HTTP::Response->new('200'));
        $test_ua->map_response(qr{baz/quux}, HTTP::Response->new('500'));

- code

    The provided coderef is passed a single argument, the [HTTP::Request](https://metacpan.org/pod/HTTP::Request), and
    returns a boolean indicating if there is a match.

        # matches all GET and POST requests
        $test_ua->map_response(sub {
                my $request = shift;
                return 1 if $request->method eq 'GET' || $request->method eq 'POST';
            },
            HTTP::Response->new('200'),
        );

- [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object

    The [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object is matched identically (including all query
    parameters, headers etc) against the provided object.

The response can be represented either as a literal [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object, or
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
then examined. When no matches have been found, a 404 response is returned.

## `map_network_response($request_description)`

Same as `map_response` above, only requests that match this description will
not use a response that you specify, but instead uses a real [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent)
to dispatch your request to the network.

If called on an instance, all options passed to the constructor (e.g. timeout)
are used for making the real network call. If called as a class method, a
pristine [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object with no customized options will be used
instead.

## `unmap_all(instance_only?)`

When called as a class method, removes all mappings set up globally (across all
objects). Mappings set up on an individual object will still remain.

When called as an object method, removes _all_ mappings both globally and on
this instance, unless a true value is passed as an argument, in which only
mappings local to the object will be removed. (Any true value will do, so you
can pass a meaningful string.)

## `register_psgi($domain, $app)`

Register a particular [PSGI](https://metacpan.org/pod/PSGI) app (code reference) to be used when requests
for a domain are received (matches are made exactly against
`$request->uri->host`).  The request is passed to the `$app` for processing,
and the [PSGI](https://metacpan.org/pod/PSGI) response is converted back to an [HTTP::Response](https://metacpan.org/pod/HTTP::Response) (you must
already have loaded [HTTP::Message::PSGI](https://metacpan.org/pod/HTTP::Message::PSGI) or equivalent, as this is not done
for you).

You can also use `register_psgi` with a regular expression as the first
argument, or any of the other forms used by `map_response`, if you wish, as
calling `$test_ua->register_psgi($domain, $app)` is equivalent to:

    $test_ua->map_response(
        $domain,
        sub { HTTP::Response->from_psgi($app->($_[0]->to_psgi)) },
    );

This feature is useful for testing your PSGI applications, or for simulating
a server so as to test your client code.

You might find using [Plack::Test](https://metacpan.org/pod/Plack::Test) or [Plack::Test::ExternalServer](https://metacpan.org/pod/Plack::Test::ExternalServer) easier
for your needs, so check those out as well.

## `unregister_psgi($domain, instance_only?)`

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

## `last_http_request_sent`

The last [HTTP::Request](https://metacpan.org/pod/HTTP::Request) object that this object (if called on an object) or
module (if called as a class method) processed, whether or not it matched a
mapping you set up earlier.

Note that this is also available via `last_http_response_received->request`.

## `last_http_response_received`

The last [HTTP::Response](https://metacpan.org/pod/HTTP::Response) object that this module returned, as a result of a
mapping you set up earlier with `map_response`. You shouldn't normally need to
use this, as you know what you responded with - you should instead be testing
how your code reacted to receiving this response.

## `last_useragent`

The last Test::LWP::UserAgent object that was used to send a request.
Obviously this only provides new information if called as a class method; you
can use this if you don't have direct control over the useragent itself, to
get the object that was used, to verify options such as the network timeout.

## `network_fallback`

Getter/setter method for the network\_fallback preference that will be used on
this object (if called as an instance method), or globally, if called as a
class method.  Note that the actual behaviour used on an object is the ORed
value of the instance setting and the global setting.

## `send_request($request)`

This is the only method from [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) that has been overridden, which
processes the [HTTP::Request](https://metacpan.org/pod/HTTP::Request), sends to the network, then creates the
[HTTP::Response](https://metacpan.org/pod/HTTP::Response) object from the reply received. Here, we loop through your
local and global domain registrations, and local and global mappings (in this
order) and returns the first match found; otherwise, a simple 404 response is
returned (unless `network_fallback` was specified as a constructor option,
in which case unmatched requests will be delivered to the network.)

All other methods from [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) are available unchanged.

# Usage with SOAP requests

## [SOAP::Lite](https://metacpan.org/pod/SOAP::Lite)

To use this module when communicating via [SOAP::Lite](https://metacpan.org/pod/SOAP::Lite) with a SOAP server (either a real one,
with live network requests, [see above](#network_fallback) or with one simulated
with mapped responses), simply do this:

    use SOAP::Lite;
    use SOAP::Transport::HTTP;
    $SOAP::Transport::HTTP::Client::USERAGENT_CLASS = 'Test::LWP::UserAgent';

You must then make all your configuration changes and mappings globally.

See also ["CHANGING THE DEFAULT USERAGENT CLASS" in SOAP::Transport](https://metacpan.org/pod/SOAP::Transport#CHANGING-THE-DEFAULT-USERAGENT-CLASS).

## [XML::Compile::SOAP](https://metacpan.org/pod/XML::Compile::SOAP)

When using [XML::Compile::SOAP](https://metacpan.org/pod/XML::Compile::SOAP) with a compiled WSDL, you can change the
useragent object via [XML::Compile::Transport::SOAPHTTP](https://metacpan.org/pod/XML::Compile::Transport::SOAPHTTP):

    my $call = $wsdl->compileClient(
        $interface_name,
        transport => XML::Compile::Transport::SOAPHTTP->new(
            user_agent => $useragent,
            address => $wsdl->endPoint,
        ),
    );

See also ["Adding HTTP headers" in XML::Compile::SOAP::FAQ](https://metacpan.org/pod/XML::Compile::SOAP::FAQ#Adding-HTTP-headers).

# MOTIVATION

Most mock libraries on the CPAN use [Test::MockObject](https://metacpan.org/pod/Test::MockObject), which is widely considered
not good practice (among other things, `@ISA` is violated, it requires
knowing far too much about the module's internals, and is very clumsy to work
with).  ([This blog entry](https://metacpan.org/pod/hashbang.ca#mocking-lwpuseragent)
is one of many that chronicles its issues.)

This module is a direct descendant of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent), exports nothing into
your namespace, and all access is via method calls, so it is fully inheritable
should you desire to add more features or override some bits of functionality.

(Aside from the constructor), it only overrides the one method in [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) that issues calls to the
network, so real [HTTP::Request](https://metacpan.org/pod/HTTP::Request) and [HTTP::Headers](https://metacpan.org/pod/HTTP::Headers) objects are used
throughout. It provides a method (`last_http_request_sent`) to access the last
[HTTP::Request](https://metacpan.org/pod/HTTP::Request), for testing things like the URI and headers that your code
sent to [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent).

# SUPPORT

Bugs may be submitted through [the RT bug tracker](https://rt.cpan.org/Public/Dist/Display.html?Name=Test-LWP-UserAgent)
(or [bug-Test-LWP-UserAgent@rt.cpan.org](https://metacpan.org/pod/bug-Test-LWP-UserAgent@rt.cpan.org)).
I am also usually active on irc, as 'ether' at `irc.perl.org`.

# ACKNOWLEDGEMENTS

[AirG Inc.](http://corp.airg.com), my former employer, and the first user of this distribution.

mst - Matt S. Trout <mst@shadowcat.co.uk>, for the better name of this
distribution, and for the PSGI registration concept.

Also Yury Zavarin, whose [Test::Mock::LWP::Dispatch](https://metacpan.org/pod/Test::Mock::LWP::Dispatch) inspired me to write this
module, and from where I borrowed some aspects of the API.

# SEE ALSO

- [Perl advent article, 2012](http://www.perladvent.org/2012/2012-12-12.html)
- [Test::Mock::LWP::Dispatch](https://metacpan.org/pod/Test::Mock::LWP::Dispatch)
- [Test::Mock::LWP::UserAgent](https://metacpan.org/pod/Test::Mock::LWP::UserAgent)
- [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent)
- [PSGI](https://metacpan.org/pod/PSGI), [HTTP::Message::PSGI](https://metacpan.org/pod/HTTP::Message::PSGI), [LWP::Protocol::PSGI](https://metacpan.org/pod/LWP::Protocol::PSGI),
- [Plack::Test](https://metacpan.org/pod/Plack::Test), [Plack::Test::ExternalServer](https://metacpan.org/pod/Plack::Test::ExternalServer)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
