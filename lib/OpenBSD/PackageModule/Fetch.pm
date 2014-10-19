package OpenBSD::PackageModule::Fetch;
use strict;
use warnings;

# Copyright (c) 2014 Andrew Fresh <andrew@afresh1.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use 5.010;

use Carp qw( croak );
use JSON::PP qw( decode_json );

sub get_cmd  { qw( ftp -o- ) }

sub new {
    my ($class, %args) = @_;
    return bless {%args}, $class;
}

sub base_url       { die 'Must be overriden in a submodule' }
sub get_dist_info  { die 'Must be overriden in a submodule' }
sub descr_for_dist { die 'Must be overriden in a submodule' }

sub fetch {
    my $self = shift;
    return $self->format_dist( $self->get_dist_info(@_) );
}

sub format_dist {
    my ($self, $di) = @_;

    $di->{makefile}->{COMMENT} =~ s/^.{57}\K.*$/.../
        if length( $di->{makefile}->{COMMENT} ) > 60;

    return $di;
}

sub _get {
    my ($self, $url) = @_;

    my $base_url = $self->base_url();

    for ( 0 .. 2 ) {
        open my $fh, '-|', $self->get_cmd, "$base_url$url" or croak $!;
        my $content = do { local $/ = undef; <$fh> };
        close $fh;
        return $content if $content;
        sleep 2 * $_;
    }

    croak "Failed to get $base_url/$url";
}

sub _get_json { return decode_json( shift->_get(@_) ) }

1;
