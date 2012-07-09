package Test::LWP::UserAgent;

use strict;
use warnings;

use parent 'LWP::UserAgent';
use Scalar::Util qw(blessed reftype);
use Storable 'freeze';
use HTTP::Date;

my $last_http_request_sent;
my $last_http_response_received;
my @response_map;

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    $self->{__last_http_request_sent} = undef;
    $self->{__last_http_response_received} = undef;
    $self->{__response_map} = [];

    # strips default User-Agent header added by LWP::UserAgent, to make it
    # easier to define literal HTTP::Requests to match against
    $self->agent(undef) if defined $self->agent and $self->agent eq $self->_agent;

    return $self;
}

sub map_response
{
    my ($self, $request_description, $response) = @_;

    warn "map_response: response is not an HTTP::Response, it's a " . blessed($response)
        unless eval { \&$response } or eval { $response->isa('HTTP::Response') };

    if (blessed $self)
    {
        push @{$self->{__response_map}}, [ $request_description, $response ];
    }
    else
    {
        push @response_map, [ $request_description, $response ];
    }
}

sub unmap_all
{
    my ($self, $instance_only) = @_;

    if (blessed $self)
    {
        $self->{__response_map} = [];
        @response_map = () if not $instance_only;
    }
    else
    {
        @response_map = ();
    }
}

sub last_http_request_sent
{
    my $self = shift;
    return blessed($self)
        ? $self->{__last_http_request_sent}
        : $last_http_request_sent;
}

sub last_http_response_received
{
    my $self = shift;
    return blessed($self)
        ? $self->{__last_http_response_received}
        : $last_http_response_received;
}

sub __is_regexp($);

sub send_request
{
    my ($self, $request) = @_;

    my $matched_response = $self->run_handlers("request_send", $request);

    foreach my $entry (@{$self->{__response_map}}, @response_map)
    {
        last if $matched_response;
        next if not defined $entry;
        my ($request_desc, $response) = @$entry;

        if (eval { $request_desc->isa('HTTP::Request') })
        {
            $matched_response = $response, last
                if freeze($request) eq freeze($request_desc);
        }
        elsif (not reftype $request_desc)
        {
            $matched_response = $response, last
                if $request->uri eq $request_desc;
        }
        elsif (eval { \&$request_desc })
        {
            $matched_response = $response, last
                if $request_desc->($request);
        }
        elsif (__is_regexp $request_desc)
        {
            $matched_response = $response, last
                if $request->uri =~ $request_desc;
        }
        else
        {
            warn 'unknown request type found in ' . blessed($self) . ' mapping!';
        }
    }

    $last_http_request_sent = $self->{__last_http_request_sent} = $request;

    my $response = defined $matched_response ? $matched_response : HTTP::Response->new(404);

    if (eval { \&$response })
    {
        $response = $response->($request);

        warn "response from coderef is not a HTTP::Response, it's a ", blessed($response)
            unless eval { $response->isa('HTTP::Response') };
    }

    $last_http_response_received = $self->{__last_http_response_received} = $response;

    # bookkeeping that the real LWP::UserAgent does
    $response->request($request);  # record request for reference
    $response->header("Client-Date" => HTTP::Date::time2str(time));
    $self->run_handlers("response_done", $response);
    $self->progress("end", $response);

    return $response;
}

sub __is_regexp($)
{
    $^V < 5.009005 ? ref(shift) eq 'Regexp' : re::is_regexp(shift);
}

1;
__END__

=pod

=head1 NAME

Test::LWP::UserAgent - a LWP::UserAgent suitable for simulating and testing network calls

=head1 SYNOPSIS

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
        qr{foo/success}, HTTP::Response->new(200, 'OK', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{foo/fail}, HTTP::Response->new(500, 'ERROR', ['Content-Type' => 'text/plain'], ''));
    Test::LWP::UserAgent->map_response(
        qr{foo/conditional},
        sub {
            my $request = shift;
            my $success = $request->uri =~ /success/;
            return HTTP::Response->new(
                ($success ? ( 200, 'OK') : (500, 'ERROR'),
                ['Content-Type' => 'text/plain'], '')
            )
        },
    );


    # <something which calls the code being tested...>

    my $last_request = Test::LWP::UserAgent->last_http_request_sent;
    is($last_request->uri, 'http://example.com/success:3000', 'URI');
    is($last_request->content, 'a=1', 'POST content');

    # <now test that your code responded to the 200 response properly...>

One common mechanism to swap out the useragent implementation is via a
lazily-built Moose attribute; if no override is provided at construction time,
default to C<LWP::UserAgent->new(%options)>.

=head1 METHODS

All methods may be called on a specific object instance, or as a class method.
If called as on a blessed object, the action performed or data returned is
limited to just that object; if called as a class method, the action or data is
global.

=over 4

=item map_response($request_description, $http_response)

With this method, you set up what L<HTTP::Response> should be returned for each
request received.

The request can be described in multiple ways:

=over 4

=item string

The string is matched identically against the URI in the request.

Example:

    $test_ua->map('http://example.com/path', HTTP::Response->new(500));

=item regexp

The regexp is matched against the URI in the request.

Example:

    $test_ua->map(qr{path1}, HTTP::Response->new(200));
    $test_ua->map(qr{path2}, HTTP::Response->new(500));

=item code

An arbitrary coderef is passed a single argument, the L<HTTP::Request>, and
returns a boolean indicating if there is a match.

    $test_ua->map(sub {
            my $request = shift;
            return 1 if $request->method eq 'GET' || $request->method eq 'POST';
        },
        HTTP::Response->new(200),
    );

=item HTTP::Request object

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

=item unmap_all(instance_only?)

When called as a class method, removes all mappings set up globally (across all
objects). Some mappings set up on an individual object may still remain.

When called as an object method, removes I<all> mappings both globally and on
this instance, unless a true value is passed as an argument, in which only
mappings local to the object will be removed. (Any true value will do, so you
can pass a meaningful string.)

=item last_http_request_sent

The last L<HTTP::Request> object that this object (if called on an object) or
module (if called as a class method) processed, whether or not it matched a
mapping you set up earlier.

=item last_http_response_received

The last L<HTTP::Response> object that this module returned, as a result of a
mapping you set up earlier with C<map_response>. You shouldn't normally need to
use this, as you know what you responded with - you should instead be testing
how your code reacted to receiving this response.

=item send_request($request)

This is the only method from L<LWP::UserAgent> that has been overridden, which
processes the L<HTTP::Request>, sends to the network, then creates the
L<HTTP::Response> object from the reply received. Here, we loop through your
local and global mappings (in this order) and returns the first match found;
otherwise, a simple 404 response is returned.

=back

All other methods from L<LWP::UserAgent> are available unchanged.

=head1 MOTIVATION

Most mock libraries on the CPAN use L<Test::MockObject>, which is widely considered
not good practice (among other things, C<@ISA> is violated, it requires
knowing far too much about the module's internals, and is very clumsy to work
with).

This module is a direct descendant of L<LWP::UserAgent>, exports nothing into
your namespace, and all access is via method calls, so it is fully inheritable
should you desire to add more features or override some bits of functionality.

(Aside from the constructor), it only overrides the one method in L<LWP::UserAgent> that issues calls to the
network, so real L<HTTP::Request> and L<HTTP::Headers> objects are used
throughout. It provides a method (C<last_http_request_sent>) to access the last
L<HTTP::Request>, for testing things like the URI and headers that your code
sent to L<LWP::UserAgent>.

=head1 TODO

=over 4

=item Integration with L<PSGI> and L<HTTP::Message::PSGI>

=item Option to locally or globally override useragent implementations via
symbol table swap

=back

=head1 ACKNOWLEDGEMENTS

L<AirG Inc.|http://corp.airg.com>, my employer, and the first user of this distribution.

mst - Matt S. Trout <mst@shadowcat.co.uk>, for kicking me in the posterior
about my previous bad testing practices.

Also Yury Zavarin, whose L<Test::Mock::LWP::Dispatch> inspired me to write this
module, and from where I borrowed some aspects of the API.

=head1 SEE ALSO

L<Test::Mock::LWP::Dispatch>

L<Test::Mock::LWP::UserAgent>

L<LWP::UserAgent>

=head1 COPYRIGHT

This software is copyright (c) 2012 by Karen Etheridge, <ether@cpan.org>.

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

