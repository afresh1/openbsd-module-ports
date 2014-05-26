package OpenBSD::PackageModule::MakePort;
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

use Carp;
use Cwd qw( getcwd );
use File::Path qw( make_path );

sub base_dir { '/tmp/generated_ports' }
sub makefile_template {
    '/usr/ports/infrastructure/templates/Makefile.template'
}

sub _cp {
    my (@args) = @_;
    system('/bin/cp', @args);
}

sub new {
    my ($class, %args) = @_;
    return bless {%args}, $class;
}

sub make_port {
    my ($self, $di) = @_;

    my $old_cwd = getcwd();
    my $dir     = $self->make_portdir($di);
    chdir $dir or croak "Couldn't chdir $dir: $!";

    $self->make_makefile($di);

    $self->make_descr($di)
        if $dir =~ m{/CPAN/}x;    # Only works most of the time

    chdir $old_cwd or croak "Couldn't chdir $old_cwd: $!";
}

sub make_portdir {
    my ($self, $di) = @_;

    my $port = $di->{port};
    my $port_dir = $self->base_dir . '/' . $port;

    make_path($port_dir) or die "Couldn't make_path $port_dir: $!"
        unless -e $port_dir;

    if (-e "/usr/ports/$port") {
        (my $dst = $port_dir) =~ s{/[^/]+$}{};
        _cp('-r', "/usr/ports/$port/", $dst);
        rename( "$port_dir/Makefile",  "$port_dir/Makefile.orig" );
        rename( "$port_dir/pkg/PLIST", "$port_dir/pkg/PLIST.orig" );
        unlink( "$port_dir/distinfo" );
    }

    return $port_dir;
}

sub parse_makefile {
    my ($self, $path) = @_;

    return unless -e $path;

    my @makefile;
    my %vars;

    my $parse = sub {
        state $line = '';
        $line .= shift;
        return if /\\\n$/x;

        if ($line =~ /^(\#?) \s*  ([A-Z_]+) \s* = (\s*) (.*)/xms) {
            my ($comment, $key, $spaces, $value) = ($1, $2, $3, $4);
            my $tabs = $spaces =~ tr/\t/\t/;
            push @makefile, {
                key       => $key,
                value     => $value,
                tabs      => $tabs,
                commented => $comment ? 1 : 0,
            };
            $vars{$key} = $value;
        }
        else {
            push @makefile, $line;
        }
        $line = '';
    };

    open my $fh, '<', $path or croak("Couldn't open $path: $!");
    $parse->($_) while <$fh>;
    close $fh;

    return {
        makefile => \@makefile,
        vars     => \%vars,
    }
}

sub make_makefile {
    my ($self, $di) = @_;

    my %configs = %{ $di->{makefile} };

    my $port = $configs{port};
    my $license = $configs{license};

    my $old_port = $self->parse_makefile("Makefile.orig") || {};

    my @makefile = @{ $old_port->{makefile} || [] };
    @makefile = (
        '# $OpenBSD$' . "\n",
        grep { $_ !~ /^\#/x }
            @{ $self->parse_makefile($self->makefile_template)->{makefile} }
    ) unless @makefile;


    my $depends_value = sub {
        my ($print_key, $value) = @_;

        return $value unless ref $value eq 'HASH';

        my $sub_tabs = "\t" x int( length($print_key) / 8 );
        $sub_tabs .= "\t" if length($print_key) % 8;
        
        my @new;
        foreach my $depend ( sort keys %{ $value } ) {
            my $v = $value->{$depend};
            push @new,
                $v->{port} . ($v->{version} ? $v->{version} : '');
        }

        return join " \\\n$sub_tabs", @new;
    };

    open my $fh, '>', 'Makefile' or die "Couldn't open Makefile: $!";

    my $last_blank;
    foreach my $line (@makefile) {
        my $is_blank = $line =~ /^[\s\n]*$/xms;
        next if $is_blank && $last_blank;

        if ($line =~ /\.include \s+ <bsd.port.mk>/x) {
            foreach my $key (sort keys %configs) {
                my $value = $configs{$key};
                next unless $value;

                my $print_key = "$key =\t";
                $value = $depends_value->( $print_key, $value )
                    if $key =~ /_DEPENDS$/;
                print $fh "$print_key$value\n";
            }
        }

        if ( ref $line eq 'HASH' ) {
            my $key = $line->{key};

            # TODO: merge in existing values for "some" ports.
            my $value = delete $configs{$key};
            next unless $value;
            my $tabs = "\t" x ($line->{tabs} || 1);
            my $print_key = "$key =$tabs";
            $value = $depends_value->( $print_key, $value )
                if $key =~ /_DEPENDS$/;

            print $fh "# $license\n"
                if $key eq 'PERMIT_PACKAGE_CDROM' && $license;

            print $fh "$print_key$value\n";
        }
        else {
            print $fh $line;
        }

        $last_blank = $is_blank;
    }
    close $fh;
}

sub make_descr {
    my ($self, $di) = @_;

    make_path('pkg') unless -e 'pkg';

    open my $fh, '>', 'pkg/DESCR' or die "Couldn't open DESCR: $!";
    print $fh $di->{descr};
    close $fh;

    return 1;
}

1;
