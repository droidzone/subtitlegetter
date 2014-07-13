#!/usr/bin/perl
# A perl script to easily get subtitles for all movies in a directory
# Usage:
# ./getsubs.pl
#
# Credits for initial script to  https://github.com/hitolaus/p5-OpenSubtitles
# Reference to API: http://trac.opensubtitles.org/projects/opensubtitles/wiki/XMLRPC
$VERSION = "1.00";

use strict;
use LWP::Simple;
use XML::RPC;
use File::Basename;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use LWP::Simple;
use Data::Dumper;
use File::Fetch;
use File::Copy;
# Globals
our $CANNED_RESPONSE; # Mock data for unit testing

#my $USER_AGENT = "p5-OpenSubtitles v1";
my $USER_AGENT = "OS Test User Agent";

sub new
{
    my($class, %args) = @_;

    my $self = bless({}, $class);

    return $self;
}

sub testapi {
    my $xmlrpc = XML::RPC->new('http://api.opensubtitles.org/xml-rpc');
    my $token = _login();
    my @args =qw//;
    my $result = $xmlrpc->call('ServerInfo', $token, @args);
    
    return $result->{xmlrpc_version};


}

sub search
{
    #my $self = shift;
    my $filename = shift or die("Need video filename");
    my $filesize = -s $filename;

    my $token = _login();
    
    my @args = [ { sublanguageid => "eng", moviehash => OpenSubtitlesHash($filename), moviebytesize => $filesize } ];
    
    my $xmlrpc = XML::RPC->new('http://api.opensubtitles.org/xml-rpc');
    my $result = $xmlrpc->call('SearchSubtitles', $token, @args);
    
    return $result->{data};
}


sub download
{
    my $self = shift;
    my $filename = shift or die("Need video filename");
    
    my @result = $self->search($filename);
    
    if (@result == 0) {
        print "Cannot find subtitles for $filename\n";
        return;
    }
    
    my $subtitle = _best_subtitle(@result);
    if (!$subtitle) {
        print "Cannot find subtitle for $filename\n";
        return;
    }
    
    my ( $name, $path, $suffix ) = fileparse( $filename, qr/\.[^.]*/ );
    
    my $subtitle_filename = "$path$name.$subtitle->{ext}";
    
    my $input = get($subtitle->{link});
    
    gunzip \$input => $subtitle_filename
        or die "gunzip failed: $GunzipError\n";
}

sub _best_subtitle
{
    my @subtitles = shift;
    
    for my $subtitle (@subtitles) {
        if (_is_subtitle_supported($subtitle)) {
            return { link => @$subtitle[0]->{SubDownloadLink}, ext =>  @$subtitle[0]->{SubFormat} };            
        }
    }
    
    return 0;
}

sub _is_subtitle_supported
{
    my $subtitle = shift;
    
    if (!$subtitle) {
        return 0;
    }
    
    return @$subtitle[0]->{SubFormat} == "srt";
}

sub _login
{
    my $un="grimy";
    my $pw="password";
    my $lang="en";
    # array LogIn( $username, $password, $language, $useragent ) 
    # As language - use ?ISO639 2 letter code http://en.wikipedia.org/wiki/List_of_ISO_639-2_codes
    my $xmlrpc = XML::RPC->new('http://api.opensubtitles.org/xml-rpc');
    my $result = $xmlrpc->call('LogIn', $un, $pw, $lang,  $USER_AGENT );
    
    return $result->{token};
}


#################################################
# Hashing functions from opensubtitles.org
#################################################
sub OpenSubtitlesHash {
    my $filename = shift or die("Need video filename");

    open my $handle, "<", $filename or die $!;
    binmode $handle;

    my $fsize = -s $filename;

    my $hash = [$fsize & 0xFFFF, ($fsize >> 16) & 0xFFFF, 0, 0];

    $hash = AddUINT64($hash, ReadUINT64($handle)) for (1..8192);

    my $offset = $fsize - 65536;
    seek($handle, $offset > 0 ? $offset : 0, 0) or die $!;

    $hash = AddUINT64($hash, ReadUINT64($handle)) for (1..8192);

    close $handle or die $!;
    return UINT64FormatHex($hash);
}

sub ReadUINT64 {
    read($_[0], my $u, 8);
    return [unpack("vvvv", $u)];
}

sub AddUINT64 {
    my $o = [0,0,0,0];
    my $carry = 0;
    for my $i (0..3) {
        if (($_[0]->[$i] + $_[1]->[$i] + $carry) > 0xffff ) {
            $o->[$i] += ($_[0]->[$i] + $_[1]->[$i] + $carry) & 0xffff;
            $carry = 1;
        } else {
            $o->[$i] += ($_[0]->[$i] + $_[1]->[$i] + $carry);
            $carry = 0;
        }
    }
    return $o;
}

sub UINT64FormatHex {
    return sprintf("%04x%04x%04x%04x", $_[0]->[3], $_[0]->[2], $_[0]->[1], $_[0]->[0]);
}
sub lp 
{
    print $_[0]."\n";
}

sub dl
{
    my $xmlrpc = XML::RPC->new('http://api.opensubtitles.org/xml-rpc');
    #array DownloadSubtitles( $token, array($IDSubtitleFile, $IDSubtitleFile,...) )
    my $token = _login();
    my @subids = { 1952609056 };
      
    my $mresult = $xmlrpc->call('DownloadSubtitles', $token, @subids );  
    print $mresult->{status};
      
      # &lp ("Number of files received:".keys $mresult->{data});
      # print "Base file:".$mresult->{data}[0]->{data};
}

sub msearch
{
    #my $self = shift;
    #array SearchSubtitles( $token, array(array('sublanguageid' => $sublanguageid, 'moviehash' => $moviehash, 'moviebytesize' => $moviesize, imdbid => $imdbid, query => 'movie name', "season" => 'season number', "episode" => 'episode number', 'tag' => tag ),array(...)), array('limit' => 500))
    my $filename = shift or die("Need video filename");
    my $sublanguageid='eng';
    my $moviehash=OpenSubtitlesHash($filename);
    my $moviesize=-s $filename;
    my $token = _login();
    my @args = [ { sublanguageid => $sublanguageid, moviehash => $moviehash, moviebytesize => $moviesize } ];

    # lp ( "Sending data:".join( ',', @args ) );
    my $xmlrpc = XML::RPC->new('http://api.opensubtitles.org/xml-rpc');
    my $result = $xmlrpc->call('SearchSubtitles', $token, @args);    
    
    &lp ("Number of subtitle files found:".keys $result->{data});
    my $count=0;
    mkdir "./Subs";
    foreach my $key ( keys $result->{data} )
    {
	$count++;
	  # print "key: $key, value: $result->{data}[$key]\n";
	  # lp("Subtitle #".($key+1));
	  # lp ("IDSubtitle:".$result->{data}[$key]->{IDSubtitle});
	# lp ("IDSubtitleFile:".$result->{data}[$key]->{IDSubtitleFile});  
	  # lp ("SubFileName:".$result->{data}[$key]->{SubFileName});
	lp ("SubDownloadLink:".$result->{data}[$key]->{SubDownloadLink});
	my $filen = $result->{data}[$key]->{SubFileName};
	my $url =$result->{data}[$key]->{SubDownloadLink};
	my $ff = File::Fetch->new(uri => $url);
	my $file = $ff->fetch() or die $ff->error;
	# lp ("Fetched as $file");
	gunzip $file => $filen
	    or die "gunzip failed: $GunzipError\n";
	unlink $file;
	  # getstore($url, $file);
	use File::Basename;
	my ($name,$path,$orgext) = fileparse($filen,qr"\..[^.]*$");
my ($mname,$mpath,$mext) = fileparse($filename,qr"\..[^.]*$");
	my $newname = $mname.$orgext;
	if ( $count == 1 ) {
	    copy($filen, $newname) or die "Copy failed: $!";
	    lp ("Downloaded: ".$newname);
	}
	move ($filen, "./Subs/") or die "Copy failed: $!";
    }

}

sub findfiles {
#Files all avi files in a directory
    my @files = glob "*.avi *.mp4 *.mkv";
    for (0..$#files){
	print "\nSearching for subtitles for $files[$_] \n";
	my $names = msearch ($files[$_]);
    }
}

print "API version:".&testapi()."\n";
findfiles;
# my $names = msearch ("24 Season 8 Episode 01 - 4PM - 5PM.avi");
# dl;
