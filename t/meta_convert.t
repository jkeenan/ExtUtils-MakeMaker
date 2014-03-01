#!perl -w

use strict;
use warnings;

BEGIN { unshift @INC, 't/lib'; }
use Test::More;
eval { require CPAN::Meta; };
plan skip_all => 'Failed to load CPAN::Meta' if $@;
plan 'no_plan';
use File::Temp qw[tempdir];
require ExtUtils::MM_Any;

my $tmpdir = tempdir( DIR => 't', CLEANUP => 1 );
chdir $tmpdir or die "chdir $tmpdir: $!";

my $METAJSON = File::Spec->catfile('_eumm', 'META_new.json');

sub ExtUtils::MM_Any::quote_literal { $_[1] }

my $new_mm = sub {
    return bless { ARGS => {@_}, @_ }, 'ExtUtils::MM_Any';
};

my $warn_ok = sub {
    my($code, $want, $name) = @_;

    my @have;
    my $ret;
    {
        local $SIG{__WARN__} = sub { push @have, @_ };
        $ret = $code->();
    }

    like join("", @have), $want, $name;
    return $ret;
};

my $version_regex = qr/['"]?version['"]?\s*:\s*['"]['"]/;
my $version_action = "they're converted to empty string";


note "Filename as version"; {
    my $mm = $new_mm->(
        DISTNAME => 'Net::FTP::Recursive',
        VERSION  => 'Recursive.pm',
    );

    my $res = $warn_ok->(
        sub { eval { $mm->metafile_target } },
        qr{Can't parse version 'Recursive.pm'}
    );
    ok $res, 'we know how to deal with bogus versions defined in Makefile.PL';
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, $version_regex, $version_action;
}


note "'undef' version from parse_version"; {
    my $mm = $new_mm->(
        DISTNAME => 'Image::Imgur',
        VERSION  => 'undef',
    );
    my $res = $warn_ok->(
        sub { eval { $mm->metafile_target } },
        qr{Can't parse version 'undef'}
    );
    ok $res, q|when there's no $VERSION in Module.pm, $self->{VERSION} = 'undef'; via MM_Unix::parse_version and we know how to deal with that|;
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, $version_regex, $version_action;
}


note "x.y.z version"; {
    my $mm = $new_mm->(
        DISTNAME => 'SQL::Library',
        VERSION  => 0.0.3,
    );

    # It would be more useful if the warning got translated to visible characters
    my $res = $warn_ok->(
        sub { eval { $mm->metafile_target } },
        qr{Can't parse version '\x00\x00\x03'}
    );
    ok $res, q|we know how to deal with our $VERSION = 0.0.3; style versions defined in the module|;
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, $version_regex, $version_action;
}


note ".5 version"; {
    my $mm = $new_mm->(
        DISTNAME => 'Array::Suffix',
        VERSION  => '.5',
    );
    my $res = $warn_ok->(
        sub { eval { $mm->metafile_target } },
        qr{Can't parse version '.5'}
    );
    ok $res, q|we know how to deal with our $VERSION = '.5'; style versions defined in the module|;
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, $version_regex, $version_action;
}


note "Non-camel case metadata"; {
    my $mm = $new_mm->(
        DISTNAME   => 'Attribute::Signature',
        META_MERGE => {
            resources => {
                repository         => 'http://github.com/chorny/Attribute-Signature',
                'Repository-clone' => 'git://github.com/chorny/Attribute-Signature.git',
            },
        },
    );
    my $res = eval { $mm->metafile_target };
    ok $res, q|we know how to deal with non-camel-cased custom meta resource keys defined in Makefile.PL|;
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, qr/x_Repositoryclone/, "they're camel-cased";
}


note "version object in provides"; {
    my $mm = $new_mm->(
        DISTNAME   => 'CPAN::Testers::ParseReport',
        VERSION    => '2.34',
        META_ADD => {
            provides => {
                "CPAN::Testers::ParseReport" => {
                    version => version->new("v1.2.3"),
                    file    => "lib/CPAN/Testers/ParseReport.pm"
                }
            }
        },
    );
    my $res = eval { $mm->metafile_target };
    my $content = do { open my $fh, '<', $METAJSON or die "$METAJSON: $!\n"; local $/; <$fh>; };
    like $content, qr/['"]?version['"]?\s*:\s*['"]v1\.2\.3['"]/;
}
