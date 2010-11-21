package Po4aBuilder;
use Module::Build;
use File::Path;
use File::Spec;

@ISA = qw(Module::Build);

sub ACTION_build {
    my $self = shift;
    $self->depends_on('code');
    $self->depends_on('po4a_build');
    $self->depends_on('distmeta'); # regenerate META.yml
    $self->depends_on('postats');
}

sub ACTION_po4a_build {
    my $self = shift;
    system("chmod -R u+w po/pod") && die;
    system("./share/po4a-build -f po4a-build.conf") && die;
    File::Path::mkpath( File::Spec->catdir( 'blib', 'manl10n' ), 0, oct(777) );
    system ("cp -R _build/po4a/man/* blib/manl10n") && die;
}

sub perl_scripts {
    return ('po4a-gettextize', 'po4a-updatepo', 'po4a-translate',
            'po4a-normalize', 'po4a', 'scripts/msguntypot');
}

sub shell_scripts {
    return ('share/po4a-build');
}

# Update po/bin/*.po files
sub ACTION_binpo {
    my $self = shift;
    my ($cmd, $sources);

    system("chmod -R u+w po/bin") && die;

    my @perl_files = sort((perl_scripts(), @{$self->rscan_dir('lib',qr{\.pm$})}));
    my @shell_files = sort(shell_scripts());
    my @all_files = (@perl_files, @shell_files);
    unless ($self->up_to_date(\@all_files, "po/bin/po4a.pot")) {
        print "XX Update po/bin/po4a-perl.pot\n";
        $sources = join ("", map {" ../../".$_ } @perl_files);
        $cmd = "cd po/bin; xgettext ";
        $cmd .= "--from-code=utf-8 ";
        $cmd .= "-L Perl ";
        $cmd .= "--add-comments ";
        $cmd .= "--msgid-bugs-address po4a\@packages.debian.org ";
        $cmd .= "--package-name po4a ";
        $cmd .= "--package-version ".$self->dist_version()." ";
        $cmd .= "$sources ";
        $cmd .= "-o po4a-perl.pot";
        system($cmd) && die;

        print "XX Update po/bin/po4a-shell.pot\n";
        $sources = join ("", map {" ../../".$_ } @shell_files);
        $cmd = "cd po/bin; xgettext ";
        $cmd .= "--from-code=utf-8 ";
        $cmd .= "-L shell ";
        $cmd .= "--add-comments ";
        $cmd .= "--msgid-bugs-address po4a\@packages.debian.org ";
        $cmd .= "--package-name po4a ";
        $cmd .= "--package-version ".$self->dist_version()." ";
        $cmd .= "$sources ";
        $cmd .= "-o po4a-shell.pot";
        system($cmd) && die;

        $cmd = "msgcat po/bin/po4a-perl.pot po/bin/po4a-shell.pot -o po/bin/po4a.pot.new";
        system($cmd) && die;

        unlink "po/bin/po4a-perl.pot" || die;
        unlink "po/bin/po4a-shell.pot" || die;

        if ( -e "po/bin/po4a.pot") {
            $diff = qx(diff -q -I'#:' -I'POT-Creation-Date:' -I'PO-Revision-Date:' po/bin/po4a.pot po/bin/po4a.pot.new);
            if ( $diff eq "" ) {
                unlink "po/bin/po4a.pot.new" || die;
                # touch it
                my ($atime, $mtime) = (time,time);
                utime $atime, $mtime, "po/bin/po4a.pot";
            } else {
                rename "po/bin/po4a.pot.new", "po/bin/po4a.pot" || die;
            }
        } else {
            rename "po/bin/po4a.pot.new", "po/bin/po4a.pot" || die;
        }
    } else {
        print "XX po/bin/po4a.pot uptodate.\n";
    }

    # update languages
    foreach (@{$self->rscan_dir('po/bin',qr{\.po$})}) {
        next if m|/.#|;
        $_ =~ /.*\/(.*)\.po$/;
        my $lang = $1;

        unless ($self->up_to_date("po/bin/po4a.pot","po/bin/$lang.po")) {
            print "XX Sync po/bin/$lang.po: ";
            system("msgmerge --previous po/bin/$lang.po po/bin/po4a.pot -o po/bin/$lang.po.new") && die;
            # Typically all that changes was a date. I'd
            # prefer not to commit such changes, so detect
            # and ignore them.
            $diff = qx(diff -q -I'#:' -I'POT-Creation-Date:' -I'PO-Revision-Date:' po/bin/$lang.po po/bin/$lang.po.new);
            if ($diff eq "") {
                unlink "po/bin/$lang.po.new" || die;
                # touch it
                my ($atime, $mtime) = (time,time);
                utime $atime, $mtime, "po/bin/$lang.po";
            } else {
                rename "po/bin/$lang.po.new", "po/bin/$lang.po" || die;
            }
        } else {
            print "XX po/bin/$lang.po uptodate.\n";
        }
        unless ($self->up_to_date("po/bin/$lang.po","blib/po/$lang/LC_MESSAGES/po4a.mo")) {
            File::Path::mkpath( File::Spec->catdir( 'blib', 'po', $lang, "LC_MESSAGES" ), 0, oct(777) );
            system("msgfmt -o blib/po/$lang/LC_MESSAGES/po4a.mo po/bin/$lang.po") && die;
        } 
    }
}

sub ACTION_install {
    my $self = shift;

    require ExtUtils::Install;
#    $self->depends_on('build');
    my $mandir = $self->install_sets($self->installdirs)->{'bindoc'};
    $mandir =~ s/\/man1$//;
    $self->install_path(manl10n => $mandir);

    my $localedir = $mandir;
    $localedir =~ s/\/man$/\/locale/;
    $self->install_path(po => $localedir);

    ExtUtils::Install::install($self->install_map, !$self->quiet, 0, $self->{args}{uninst}||0);
}

sub ACTION_dist {
    my ($self) = @_;

    $self->depends_on('test');
    $self->depends_on('binpo');
    $self->depends_on('distdir');

    system("./share/po4a-build --pot-only -f ./po4a-build.conf") and die;

    my $dist_dir = $self->dist_dir;

    if ( -e "$dist_dir.tar.gz") {
        # Delete the distfile if it already exists
        system ("rm $dist_dir.tar.gz") && die;
    }

    $self->make_tarball($dist_dir);
    $self->delete_filetree($dist_dir);
} 

sub ACTION_postats {
    my $self = shift;
    $self->depends_on('binpo');
    $self->postats("po/bin");
    $self->postats("po/pod");
    $self->postats("po/www") if -d "po/www";
}

sub postats {
    my ($self,$dir) = (shift,shift);
    my $potsize = `(cd $dir;ls -sh *.pot) | sed -n -e 's/^ *\\([^[:blank:]]*\\).*\$/\\1/p'`;
    $potsize =~ /(.*)/;
    print "$dir (pot: $1)\n";
    my @files = @{$self->rscan_dir($dir,qr{\.po$})};
    foreach (sort @files) {
        $file = $_;
        $file =~ /.*\/(.*)\.po$/;
        my $lang = $1;
        my $stat = `msgfmt -o /dev/null -c -v --statistics $file 2>&1`;
        print "  $lang: $stat";
    }
}
    
1;