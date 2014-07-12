package OpenBSD::PackageModule::Utils;
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

use parent qw( Exporter );

use Carp;
use Cwd qw( getcwd );

our @EXPORT_OK = qw(
    base_dir
    port_dir
    makefile_template

    dist_is_up_to_date
    port_value
    make_in_port
);

sub port_dir { $ENV{PORTSDIR} || '/usr/ports' }
sub base_dir { port_dir() . '/mystuff' }
sub makefile_template {
    port_dir() . '/infrastructure/templates/Makefile.template'
}

sub dist_is_up_to_date {
    my ($di) = @_;
    my $current_distname = port_value( $di, 'DISTNAME' );
    return $current_distname eq $di->{distname};
}

sub port_value {
    my ( $di, $variable ) = @_;
    my $value = make_in_port( $di, "show=$variable" );
    chomp $value;
    return $value;
}

sub make_in_port {
    my ( $di, @args ) = @_;

    my $old_cwd = getcwd();
    my $port    = $di->{port} || die "Dist Info has no port";
    my $dir;
    foreach my $d ( base_dir(), port_dir() ) {
        if ( -d "$d/$port" ) {
            $dir = "$d/$port";
            last;
        }
    }
    return '' unless $dir;

    chdir $dir or die "Couldn't chdir $dir: $!";

    open my $fh, '-|', 'make', @args or die "Couldn't launch make";
    my $output = do { local $/ = undef; <$fh> };
    close $fh;

    chdir $old_cwd or die "Couldn't chdir $old_cwd: $!";

    return $output;
}

1;
