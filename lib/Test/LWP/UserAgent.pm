use strict;
use warnings;
package Test::LWP::UserAgent;
# ABSTRACT: a LWP::UserAgent suitable for simulating and testing network calls

use parent 'LWP::UserAgent';
use Scalar::Util qw(blessed reftype);
use Storable 'freeze';
use HTTP::Request;
use HTTP::Response;
use URI;
use HTTP::Date;
use HTTP::Status qw(:constants status_message);
use Try::Tiny;
use Safe::Isa;
use Carp;
use namespace::clean;

my @response_map;
my $network_fallback;
my $last_useragent;

sub new
{
    my ($class, %options) = @_;

    my $_network_fallback = delete $options{network_fallback};

    my $self = $class->SUPER::new(%options);
    $self->{__last_http_request_sent} = undef;
    $self->{__last_http_response_received} = undef;
    $self->{__response_map} = [];
    $self->{__network_fallback} = $_network_fallback;

    # strips default User-Agent header added by LWP::UserAgent, to make it
    # easier to define literal HTTP::Requests to match against
    $self->agent(undef) if defined $self->agent and $self->agent eq $self->_agent;

    return $self;
}

sub map_response
{
    my ($self, $request_description, $response) = @_;

    if (not defined $response and blessed $self)
    {
        # mask a global domain mapping
        my $matched;
        foreach my $mapping (@{$self->{__response_map}})
        {
            if ($mapping->[0] eq $request_description)
            {
                $matched = 1;
                undef $mapping->[1];
            }
        }

        push @{$self->{__response_map}}, [ $request_description, undef ]
            if not $matched;

        return;
    }

    if (not $response->$_isa('HTTP::Response') and try { $response->can('request') })
    {
        my $oldres = $response;
        $response = sub {
            $oldres->request($_[0]) };
    }

    carp 'map_response: response is not a coderef or an HTTP::Response, it\'s a ',
            (blessed($response) || 'non-object')
        unless __isa_coderef($response) or $response->$_isa('HTTP::Response');

    if (blessed $self)
    {
        push @{$self->{__response_map}}, [ $request_description, $response ];
    }
    else
    {
        push @response_map, [ $request_description, $response ];
    }
}

sub map_network_response
{
    my ($self, $request_description) = @_;

    if (blessed $self)
    {
        # we cannot call ::request here, or we end up in an infinite loop
        push @{$self->{__response_map}},
            [ $request_description, sub { $self->SUPER::send_request($_[0]) } ];
    }
    else
    {
        push @response_map,
            [ $request_description, sub { LWP::UserAgent->new->send_request($_[0]) } ];
    }
}

sub unmap_all
{
    my ($self, $instance_only) = @_;

    if (blessed $self)
    {
        $self->{__response_map} = [];
        @response_map = () unless $instance_only;
    }
    else
    {
        carp 'instance-only unmap requests make no sense when called globally'
            if $instance_only;
        @response_map = ();
    }
}

sub register_psgi
{
    my ($self, $domain, $app) = @_;

    return $self->map_response($domain, undef) if not defined $app;

    carp 'register_psgi: app is not a coderef, it\'s a ', ref($app)
        unless __isa_coderef($app);

    carp 'register_psgi: did you forget to load HTTP::Message::PSGI?'
        unless HTTP::Request->can('to_psgi') and HTTP::Response->can('from_psgi');

    return $self->map_response(
        $domain,
        sub { HTTP::Response->from_psgi($app->($_[0]->to_psgi)) },
    );
}

sub unregister_psgi
{
    my ($self, $domain, $instance_only) = @_;

    if (blessed $self)
    {
        @{$self->{__response_map}} = grep { $_->[0] ne $domain } @{$self->{__response_map}};

        @response_map = grep { $_->[0] ne $domain } @response_map
            unless $instance_only;
    }
    else
    {
        @response_map = grep { $_->[0] ne $domain } @response_map;
    }
}

sub last_http_request_sent
{
    my $self = shift;
    return blessed($self)
        ? $self->{__last_http_request_sent}
        : $last_useragent
            ? $last_useragent->last_http_request_sent
            : undef;
}

sub last_http_response_received
{
    my $self = shift;
    return blessed($self)
        ? $self->{__last_http_response_received}
        : $last_useragent
            ? $last_useragent->last_http_response_received
            : undef;
}

sub last_useragent
{
    return $last_useragent;
}

sub network_fallback
{
    my ($self, $value) = @_;

    if (@_ == 1)
    {
        return blessed $self
            ? $self->{__network_fallback}
            : $network_fallback;
    }

    return $self->{__network_fallback} = $value if blessed $self;
    $network_fallback = $value;
}

sub send_request
{
    my ($self, $request, $arg, $size) = @_;

    $self->progress('begin', $request);
    my $matched_response = $self->run_handlers('request_send', $request);

    my $uri = $request->uri;

    foreach my $entry (@{$self->{__response_map}}, @response_map)
    {
        last if $matched_response;
        next if not defined $entry;
        my ($request_desc, $response) = @$entry;

        if ($request_desc->$_isa('HTTP::Request'))
        {
            local $Storable::canonical = 1;
            $matched_response = $response, last
                if freeze($request) eq freeze($request_desc);
        }
        elsif (__is_regexp($request_desc))
        {
            $matched_response = $response, last
                if $uri =~ $request_desc;
        }
        elsif (__isa_coderef($request_desc))
        {
            $matched_response = $response, last
                if $request_desc->($request);
        }
        else
        {
            $uri = URI->new($uri) if not $uri->$_isa('URI');
            $matched_response = $response, last
                if $uri->host eq $request_desc;
        }
    }

    $last_useragent = $self;
    $self->{__last_http_request_sent} = $request;

    if (not defined $matched_response and
        ($self->{__network_fallback} or $network_fallback))
    {
        my $response = $self->SUPER::send_request($request, $arg, $size);
        $self->{__last_http_response_received} = $response;
        return $response;
    }

    my $response = defined $matched_response
        ? $matched_response
        : HTTP::Response->new('404');

    if (__isa_coderef($response))
    {
        # emulates handling in LWP::UserAgent::send_request
        if ($self->use_eval)
        {
            $response = try { $response->($request) }
            catch {
                my $exception = $_;
                if ($exception->$_isa('HTTP::Response'))
                {
                    $response = $exception;
                }
                else
                {
                    my $full = $exception;
                    (my $status = $exception) =~ s/\n.*//s;
                    $status =~ s/ at .* line \d+.*//s;  # remove file/line number
                    my $code = ($status =~ s/^(\d\d\d)\s+//) ? $1 : HTTP_INTERNAL_SERVER_ERROR;
                    # note that _new_response did not always take a fourth
                    # parameter - content used to always be "$code $message"
                    $response = LWP::UserAgent::_new_response($request, $code, $status, $full);
                }
            }
        }
        else
        {
            $response = $response->($request);
        }
    }

    if (not $response->$_isa('HTTP::Response'))
    {
        carp 'response from coderef is not a HTTP::Response, it\'s a ',
            (blessed($response) || 'non-object');
        $response = LWP::UserAgent::_new_response($request, HTTP_INTERNAL_SERVER_ERROR, status_message(HTTP_INTERNAL_SERVER_ERROR));
    }
    else
    {
        $response->request($request);  # record request for reference
        $response->header('Client-Date' => HTTP::Date::time2str(time));
    }

    # handle any additional arguments that were provided, such as saving the
    # content to a file.  this also runs additional handlers for us.
    my $protocol = LWP::Protocol->new('no-schemes-from-TLWPUA', $self);
    my $complete;
    $response = $protocol->collect($arg, $response, sub {
        # remove content from $response and stream it back
        return \'' if $complete;
        my $content = $response->content;
        $response->content('');
        $complete++;
        \$content;
    });

    $self->run_handlers('response_done', $response);
    $self->progress('end', $response);

    $self->{__last_http_response_received} = $response;

    return $response;
}

sub __isa_coderef
{
    ref $_[0] eq 'CODE'
        or (reftype($_[0]) || '') eq 'CODE'
        or overload::Method($_[0], '&{}')
}

sub __is_regexp
{
    $^V < 5.009005 ? ref(shift) eq 'Regexp' : re::is_regexp(shift);
}

1;
__END__

=pod

=head1 SYNOPSIS

In your application code:

    use URI;
    use HTTP::Request::Common;
    use LWP::UserAgent;

    my $ua = $self->useragent || LWP::UserAgent->new;

    my $uri = URI->new('http://example.com');
    $uri->port('3000');
    $uri->path('success');
    my $request = POST($uri, a => 1);
    my $response = $ua->request($request);

Then, in your tests:

    use Test::LWP::UserAgent;
    use Test::More;

    Test::LWP::UserAgent->map_response(
        qr{example.com/success}, HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{example.com/fail}, HTTP::Response->new('500', 'ERROR', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{example.com/conditional},
        sub {
            my $request = shift;
            my $success = $request->uri =~ /success/;
            return HTTP::Response->new(
                ($success ? ( '200', 'OK') : ('500', 'ERROR'),
                ['Content-Type' => 'text/plain'], '')
            )
        },
    );

OR, you can use a L<PSGI> app to handle the requests:

    use HTTP::Message::PSGI;
    Test::LWP::UserAgent->register_psgi('example.com' => sub {
        my $env = shift;
        # logic here...
        [ '200', [ 'Content-Type' => 'text/plain' ], [ 'some body' ] ],
    );

And then:

    # <something which calls the code being tested...>

    my $last_request = Test::LWP::UserAgent->last_http_request_sent;
    is($last_request->uri, 'http://example.com/success:3000', 'URI');
    is($last_request->content, 'a=1', 'POST content');

    # <now test that your code responded to the 200 response properly...>

This feature is useful for testing your PSGI applications (you may or may not find
using L<Plack::Test> easier), or for simulating a server so as to test your
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
        '200',
        'I should have gotten an OK response',
    );

Note that L<LWP::UserAgent> itself is not monkey-patched - you must use
this module (or a subclass) to send your request, or it cannot be caught and
processed.

One common mechanism to swap out the useragent implementation is via a
lazily-built Moose attribute; if no override is provided at construction time,
default to C<< LWP::UserAgent->new(%options) >>.

=head1 METHODS

=over

=item * C<new>

Accepts all options as in L<LWP::UserAgent>, including C<use_eval>, an
undocumented boolean which is enabled by default. When set, sending the HTTP
request is wrapped in an C<< eval {} >>, allowing all exceptions to be caught
and an appropriate error response (usually HTTP 500) to be returned. You may
want to unset this if you really want to test extraordinary errors within your
networking code.  Normally, you should leave it alone, as L<LWP::UserAgent> and
this module are capable of handling normal errors.

Plus, this option is added:

=over

=item * C<< network_fallback => <boolean> >>

If true, requests passing through this object that do not match a
previously-configured mapping or registration will be directed to the network.
(To only divert I<matched> requests rather than unmatched requests, use
C<map_network_response>, see below.)

This option is also available as a read/write accessor via
C<< $useragent->network_fallback(<value?>) >>.

=back

All other methods may be called on a specific object instance, or as a class method.
If called as on a blessed object, the action performed or data returned is
limited to just that object; if called as a class method, the action or data is
global.

=item * C<map_response($request_description, $http_response)>

With this method, you set up what L<HTTP::Response> should be returned for each
request received.

The request match specification can be described in multiple ways:

=over

=item * string

The string is matched identically against the C<host> field of the L<URI> in the request.

Example:

    $test_ua->map_response('example.com', HTTP::Response->new('500'));

=item * regexp

The regexp is matched against the URI in the request.

Example:

    $test_ua->map_response(qr{foo/bar}, HTTP::Response->new('200'));
    $test_ua->map_response(qr{baz/quux}, HTTP::Response->new('500'));

=item * code

An arbitrary coderef is passed a single argument, the L<HTTP::Request>, and
returns a boolean indicating if there is a match.

    $test_ua->map_response(sub {
            my $request = shift;
            return 1 if $request->method eq 'GET' || $request->method eq 'POST';
        },
        HTTP::Response->new('200'),
    );

=item * L<HTTP::Request> object

The L<HTTP::Request> object is matched identically (including all query
parameters, headers etc) against the provided object.

=back

The response can be represented either as a literal L<HTTP::Request> object, or
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

=item * C<map_network_response($request_description)>

Same as C<map_response> above, only requests that match this description will
not use a response that you specify, but instead uses a real L<LWP::UserAgent>
to dispatch your request to the network.

If called on an instance, all options passed to the constructor (e.g. timeout)
are used for making the real network call. If called as a class method, a
pristine L<LWP::UserAgent> object with no customized options will be used
instead.

=item * C<unmap_all(instance_only?)>

When called as a class method, removes all mappings set up globally (across all
objects). Mappings set up on an individual object will still remain.

When called as an object method, removes I<all> mappings both globally and on
this instance, unless a true value is passed as an argument, in which only
mappings local to the object will be removed. (Any true value will do, so you
can pass a meaningful string.)

=item * C<register_psgi($domain, $app)>

Register a particular L<PSGI> app (code reference) to be used when requests
for a domain are received (matches are made exactly against
C<< $request->uri->host >>).  The request is passed to the C<$app> for processing,
and the L<PSGI> response is converted back to an L<HTTP::Response> (you must
already have loaded L<HTTP::Message::PSGI> or equivalent, as this is not done
for you).

You can also use C<register_psgi> with a regular expression as the first
argument, or any of the other forms used by C<map_response>, if you wish, as
calling C<< $test_ua->register_psgi($domain, $app) >> is equivalent to:

    $test_ua->map_response(
        $domain,
        sub { HTTP::Response->from_psgi($app->($_[0]->to_psgi)) },
    );

=item * C<unregister_psgi($domain, instance_only?)>

When called as a class method, removes a domain->PSGI app entry that had been
registered globally.  Some mappings set up on an individual object may still
remain.

When called as an object method, removes a domain registration that was made
both globally and locally, unless a true value was passed as the second
argument, in which case only the registration local to the object will be
removed. This allows a different mapping made globally to take over.

If you want to mask a global registration on just one particular instance,
then add C<undef> as a mapping on your instance:

    $useragent->map_response($domain, undef);

=item * C<last_http_request_sent>

The last L<HTTP::Request> object that this object (if called on an object) or
module (if called as a class method) processed, whether or not it matched a
mapping you set up earlier.

Note that this is also available via C<< last_http_response_received->request >>.

=item * C<last_http_response_received>

The last L<HTTP::Response> object that this module returned, as a result of a
mapping you set up earlier with C<map_response>. You shouldn't normally need to
use this, as you know what you responded with - you should instead be testing
how your code reacted to receiving this response.

=item * C<last_useragent>

The last Test::LWP::UserAgent object that was used to send a request.
Obviously this only provides new information if called as a class method; you
can use this if you don't have direct control over the useragent itself, to
get the object that was used, to verify options such as the network timeout.

=item * C<network_fallback>

Getter/setter method for the network_fallback preference that will be used on
this object (if called as an instance method), or globally, if called as a
class method.  Note that the actual behaviour used on an object is the ORed
value of the instance setting and the global setting.

=item * C<send_request($request)>

This is the only method from L<LWP::UserAgent> that has been overridden, which
processes the L<HTTP::Request>, sends to the network, then creates the
L<HTTP::Response> object from the reply received. Here, we loop through your
local and global domain registrations, and local and global mappings (in this
order) and returns the first match found; otherwise, a simple 404 response is
returned (unless C<network_fallback> was specified as a constructor option,
in which case unmatched requests will be delivered to the network.)

=back

All other methods from L<LWP::UserAgent> are available unchanged.

=head1 Usage with SOAP requests

=over

=item * L<SOAP::Lite>

To use this module when communicating via L<SOAP::Lite> with a SOAP server (either a real one,
with live network requests, L<see above|/network_fallback> or with one simulated
with mapped responses), simply do this:

    use SOAP::Lite;
    use SOAP::Transport::HTTP;
    $SOAP::Transport::HTTP::Client::USERAGENT_CLASS = 'Test::LWP::UserAgent';

You must then make all your configuration changes and mappings globally.

See also L<SOAP::Transport/CHANGING THE DEFAULT USERAGENT CLASS>.

=item * L<XML::Compile::SOAP>

When using L<XML::Compile::SOAP> with a compiled WSDL, you can change the
useragent object via L<XML::Compile::Transport::SOAPHTTP>:

    my $call = $wsdl->compileClient(
        $interface_name,
        transport => XML::Compile::Transport::SOAPHTTP->new(
            user_agent => $useragent,
            address => $wsdl->endPoint,
        ),
    );

See also L<XML::Compile::SOAP::FAQ/Adding HTTP headers>.

=back

=head1 MOTIVATION

Most mock libraries on the CPAN use L<Test::MockObject>, which is widely considered
not good practice (among other things, C<@ISA> is violated, it requires
knowing far too much about the module's internals, and is very clumsy to work
with).  (L<This blog entry|hashbang.ca/2011/09/23/mocking-lwpuseragent>
is one of many that chronicles its issues.)

This module is a direct descendant of L<LWP::UserAgent>, exports nothing into
your namespace, and all access is via method calls, so it is fully inheritable
should you desire to add more features or override some bits of functionality.

(Aside from the constructor), it only overrides the one method in L<LWP::UserAgent> that issues calls to the
network, so real L<HTTP::Request> and L<HTTP::Headers> objects are used
throughout. It provides a method (C<last_http_request_sent>) to access the last
L<HTTP::Request>, for testing things like the URI and headers that your code
sent to L<LWP::UserAgent>.

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Test-LWP-UserAgent>
(or L<bug-Test-LWP-UserAgent@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 ACKNOWLEDGEMENTS

L<AirG Inc.|http://corp.airg.com>, my employer, and the first user of this distribution.

mst - Matt S. Trout <mst@shadowcat.co.uk>, for the better name of this
distribution, and for the PSGI registration concept.

Also Yury Zavarin, whose L<Test::Mock::LWP::Dispatch> inspired me to write this
module, and from where I borrowed some aspects of the API.

=head1 SEE ALSO

L<entry for Perl Advent 2012|http://www.perladvent.org/2012/2012-12-12.html>

L<Test::Mock::LWP::Dispatch>

L<Test::Mock::LWP::UserAgent>

L<LWP::UserAgent>

L<PSGI>, L<HTTP::Message::PSGI>, L<LWP::Protocol::PSGI>,
L<Plack::Test>, L<Plack::Test::ExternalServer>

=cut
