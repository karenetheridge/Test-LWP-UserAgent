# NAME

Test::LWP::UserAgent - a LWP::UserAgent suitable for simulating and testing network calls

# VERSION

version 0.006-TRIAL

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

OR, you can use a [PSGI](http://search.cpan.org/perldoc?PSGI) app to handle the requests (_new, in v0.006-TRIAL_):

    use HTTP::Message::PSGI;
    Test::LWP::UserAgent->register_domain('example.com' => sub {
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

One common mechanism to swap out the useragent implementation is via a
lazily-built Moose attribute; if no override is provided at construction time,
default to `LWP::UserAgent-`new(%options)>.

# METHODS

All methods may be called on a specific object instance, or as a class method.
If called as on a blessed object, the action performed or data returned is
limited to just that object; if called as a class method, the action or data is
global.

- `map_response($request_description, $http_response)`

With this method, you set up what [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) should be returned for each
request received.

The request can be described in multiple ways:

    - string

    The string is matched identically against the URI in the request.

    Example:

        $test_ua->map('http://example.com/path', HTTP::Response->new(500));

    - regexp

    The regexp is matched against the URI in the request.

    Example:

        $test_ua->map(qr{path1}, HTTP::Response->new(200));
        $test_ua->map(qr{path2}, HTTP::Response->new(500));

    - code

    An arbitrary coderef is passed a single argument, the [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), and
    returns a boolean indicating if there is a match.

        $test_ua->map(sub {
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

- `unmap_all(instance_only?)`

When called as a class method, removes all mappings set up globally (across all
objects). Mappings set up on an individual object will still remain.

When called as an object method, removes _all_ mappings both globally and on
this instance, unless a true value is passed as an argument, in which only
mappings local to the object will be removed. (Any true value will do, so you
can pass a meaningful string.)

- `register_domain($domain, $app)`

_New, in v0.006-TRIAL_

Register a particular [PSGI](http://search.cpan.org/perldoc?PSGI) app (code reference) to be used when requests
for a domain are received (matches are made exactly against
`$request-`uri->host>).  The request is passed to the `$app` for processing,
and the [PSGI](http://search.cpan.org/perldoc?PSGI) response is converted back to an [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) (you must
already have loaded[HTTP::Message::PSGI](http://search.cpan.org/perldoc?HTTP::Message::PSGI) or equivalent, as this is not done
for you).

Note that domain registrations take priority over response mappings. (_This
ordering may change._)  Also, instance registrations take priority over global
(class method) registrations.

- `unregister_domain($domain, instance_only?)`

_New, in v0.006-TRIAL_

When called as a class method, removes a domain->PSGI app entry that had been
registered globally.  Some mappings set up on an individual object may still
remain.

When called as an object method, removes a domain registration that was made
both globally and locally, unless a true value was passed as the second
argument, in which case only the registration local to the object will be
removed. This allows a different mapping made globally to take over.  However,
if the only registration was global to begin with, _and_ you passed a true
value as the second argument, use of that domain registration will be blocked
_just from that instance_, but will continue to be available from other
instances.

- `unregister_all(instance_only?)`

_New, in v0.006-TRIAL_

When called as a class method, removes all domain registrations set up
globally (across all objects). Registrations set up on an individual object
will still remain.

When called as an object method, removes _all_ registrations both globally
and on this instance, unless a true value is passed as an argument, in which
only registrations local to the object will be removed. (Any true value will
do, so you can pass a meaningful string.) (There is _not_ special logic for
blocking registrations from certain instances as available in
`unregister_domain`.)

- `last_http_request_sent`

The last [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request) object that this object (if called on an object) or
module (if called as a class method) processed, whether or not it matched a
mapping you set up earlier.

- `last_http_response_received`

The last [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) object that this module returned, as a result of a
mapping you set up earlier with `map_response`. You shouldn't normally need to
use this, as you know what you responded with - you should instead be testing
how your code reacted to receiving this response.

- `send_request($request)`

This is the only method from [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) that has been overridden, which
processes the [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), sends to the network, then creates the
[HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) object from the reply received. Here, we loop through your
local and global domain registrations, and local and global mappings (in this
order) and returns the first match found; otherwise, a simple 404 response is
returned.

All other methods from [LWP::UserAgent](http://search.cpan.org/perldoc?LWP::UserAgent) are available unchanged.

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

# TODO (possibly)

- Option to locally or globally override useragent implementations via
symbol table swap

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

# COPYRIGHT

This software is copyright (c) 2012 by Karen Etheridge, <ether@cpan.org>.

# LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
